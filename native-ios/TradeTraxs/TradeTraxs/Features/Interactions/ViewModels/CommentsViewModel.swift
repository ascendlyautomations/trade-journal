import Foundation
import Observation

@Observable
@MainActor
final class CommentsViewModel {
    private(set) var comments: [InteractionComment] = []
    private(set) var isLoading = false
    private(set) var isPosting = false
    private(set) var errorMessage: String?
    private(set) var likesByCommentID: [CommentID: CommentLikeSnapshot] = [:]
    var sort: CommentSortOrder = .oldest
    var draft = ""
    private(set) var replyTarget: CommentThreadSupport.ReplyTarget?
    private(set) var composerFocusToken = UUID()
    private(set) var scrollToThreadBottomToken: UInt64 = 0
    /// When true, list growth triggers scroll-to-bottom (keyboard stays up after send).
    var maintainKeyboardScrollAnchor = false

    var showsTradePicker = false
    var isLoadingTradePicker = false
    private(set) var tradePickerTrades: [Trade] = []
    var pendingSharedTrade: Trade?

    let target: InteractionTarget

    private let repository: any InteractionRepository
    private let tradesRepository: (any TradeRepository)?
    private let engagementStore: EngagementStore
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache?
    private let realtimeHub: RealtimeHub?
    private let commentLikeSource: CommentLikeSource
    private let contentOwnerUserID: String?
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?
    private var commentLikeRealtimeTask: Task<Void, Never>?
    private var commentPinRealtimeTask: Task<Void, Never>?
    private var commentLikeRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var commentPinRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var trackedCommentIDs: [String] = []
    private var busyCommentIDs: Set<CommentID> = []
    private var busyPinCommentIDs: Set<CommentID> = []
    private var commentLikeMutationEpoch: [CommentID: UInt64] = [:]
    private var expandedReplyThreads: Set<CommentID> = []
    private var viewerUserID: String?
    private(set) var sharedTrades: [TradeID: Trade] = [:]

    init(
        target: InteractionTarget,
        repository: any InteractionRepository,
        engagementStore: EngagementStore,
        session: any SessionProviding,
        contentOwnerUserID: String? = nil,
        detailCache: DetailPresentationCache? = nil,
        realtimeHub: RealtimeHub? = nil,
        trades: (any TradeRepository)? = nil
    ) {
        self.target = target
        self.repository = repository
        self.tradesRepository = trades
        self.engagementStore = engagementStore
        self.session = session
        self.contentOwnerUserID = contentOwnerUserID
        self.detailCache = detailCache
        self.realtimeHub = realtimeHub
        self.commentLikeSource = CommentLikeSource.from(target.kind)
    }

    func sharedTrade(for comment: InteractionComment) -> Trade? {
        guard let id = comment.sharedTradeID else { return nil }
        return sharedTrades[id]
    }

    func presentTradePicker() {
        ExperienceHaptics.play(.selection)
        showsTradePicker = true
    }

    func clearPendingSharedTrade() {
        pendingSharedTrade = nil
    }

    func stageSharedTrade(_ trade: Trade) {
        pendingSharedTrade = trade
        sharedTrades[trade.id] = trade
        showsTradePicker = false
        composerFocusToken = UUID()
    }

    func loadTradePickerIfNeeded() async {
        guard tradePickerTrades.isEmpty, !isLoadingTradePicker else { return }
        guard let tradesRepository else { return }
        guard let viewerID = await session.currentUserID.map({ ProfileID($0.rawValue) }) else { return }
        isLoadingTradePicker = true
        defer { isLoadingTradePicker = false }
        if viewerID.rawValue.hasPrefix("dev-") {
            tradePickerTrades = TradeShareFixtures.sampleTrades(ownerID: viewerID)
            return
        }
        do {
            let page = try await tradesRepository.trades(
                ownedBy: viewerID,
                accountID: nil,
                page: PageRequest(limit: 40),
                publicOnly: false
            )
            let previews = page.items.map {
                TradeSummaryMapper.previewTrade(
                    from: TradeSummaryMapper.summary(fromPartialListTrade: $0)
                )
            }
            tradePickerTrades = CommentTradeShareSupport.eligibleForAttachment(
                previews,
                viewerID: viewerID
            )
        } catch {
            tradePickerTrades = []
        }
    }

    private func hydrateSharedTrades(from comments: [InteractionComment]) async {
        let ids = Set(comments.compactMap(\.sharedTradeID))
        guard !ids.isEmpty, let tradesRepository else { return }
        let missing = ids.filter { sharedTrades[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            for tradeID in missing {
                let trade = try await tradesRepository.trade(id: tradeID)
                sharedTrades[tradeID] = trade
                detailCache?.seedPresentationSeed(TradeSummaryMapper.presentationSeed(fromListTrade: trade))
            }
        } catch {
            // Keep cards in loading state until next refresh.
        }
    }

    private func requestThreadScrollToBottom() {
        scrollToThreadBottomToken &+= 1
    }

    var topLevelComments: [InteractionComment] {
        CommentPinSemantics.sortedTopLevel(
            comments.filter { !$0.isReply },
            order: sort
        )
    }

    var canLikeComments: Bool {
        viewerUserID != nil && !target.id.hasPrefix("dev-")
    }

    func canPinComment(_ comment: InteractionComment) -> Bool {
        guard !comment.isReply, !comment.id.rawValue.hasPrefix("local-") else { return false }
        return CommentPinSemantics.canPinComment(
            viewerUserID: viewerUserID,
            contentOwnerUserID: contentOwnerUserID
        )
    }

    func isCommentPinBusy(_ commentID: CommentID) -> Bool {
        busyPinCommentIDs.contains(commentID)
    }

    func likeSnapshot(for commentID: CommentID) -> CommentLikeSnapshot {
        likesByCommentID[commentID] ?? .empty
    }

    func isCommentLikeBusy(_ commentID: CommentID) -> Bool {
        busyCommentIDs.contains(commentID)
    }

    func replies(to rootID: CommentID) -> [InteractionComment] {
        CommentThreadSupport.replies(for: rootID, in: comments)
    }

    func isReplyThreadExpanded(_ rootID: CommentID) -> Bool {
        expandedReplyThreads.contains(rootID)
    }

    func toggleReplyThread(_ rootID: CommentID) {
        if expandedReplyThreads.contains(rootID) {
            expandedReplyThreads.remove(rootID)
        } else {
            expandedReplyThreads.insert(rootID)
        }
        ExperienceHaptics.play(.selection)
    }

    func beginReply(to comment: InteractionComment) {
        let target = CommentThreadSupport.buildReplyTarget(for: comment, allComments: comments)
        replyTarget = target
        draft = CommentThreadSupport.replyMentionPrefix(username: target.mentionUsername)
        composerFocusToken = UUID()
        expandedReplyThreads.insert(target.parentCommentID)
        ExperienceHaptics.play(.selection)
    }

    func cancelReply() {
        replyTarget = nil
        draft = ""
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        loadTask = Task { await refresh() }
    }

    func refresh() async {
        isLoading = comments.isEmpty
        errorMessage = nil
        viewerUserID = await session.currentUserID?.rawValue
        do {
            if target.id.hasPrefix("dev-") {
                comments = []
                likesByCommentID = [:]
                hasLoaded = true
                stopCommentRealtime()
            } else {
                let loaded = try await repository.comments(for: target, order: sort)
                guard !Task.isCancelled else { return }
                comments = mergeCommentsFromServer(loaded)
                hasLoaded = true
                engagementStore.replaceCommentCount(loaded.count, on: target)
                await loadCommentLikeMeta(for: loaded)
                await hydrateSharedTrades(from: comments)
                restartCommentLikeRealtime(for: loaded)
                restartCommentPinRealtime()
            }
        } catch {
            errorMessage = ProfileSectionSupport.message(for: error)
        }
        isLoading = false
        loadTask = nil
    }

    func setSort(_ order: CommentSortOrder) {
        guard sort != order else { return }
        sort = order
        ExperienceHaptics.play(.selection)
        Task { await refresh() }
    }

    func submit() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let sharedTrade = pendingSharedTrade
        guard (!text.isEmpty || sharedTrade != nil), !isPosting else { return }

        let parentID = replyTarget?.parentCommentID
        let capturedReplyTarget = replyTarget
        let capturedSharedTrade = sharedTrade

        isPosting = true
        defer { isPosting = false }

        let sessionUserID = await session.currentUserID
        guard case .viewer(let userID) = SessionViewerIdentity.resolve(
            userID: sessionUserID,
            demoExperienceActive: AppLaunchController.shared.isDemoExperienceActive
        ) else {
            errorMessage = SessionViewerIdentity.sessionUnavailableMessage
            return
        }
        let cachedViewer = detailCache?.profile(id: userID)
        let optimisticID = CommentID("local-\(UUID().uuidString)")
        let optimistic = InteractionComment(
            id: optimisticID,
            target: target,
            authorProfileID: userID,
            authorUsername: cachedViewer?.username,
            authorDisplayName: cachedViewer?.displayName,
            authorAvatarURL: cachedViewer?.avatar?.id,
            body: text,
            sharedTradeID: sharedTrade?.id,
            parentCommentID: parentID,
            createdAt: Date(),
            isPinned: false
        )
        let previous = comments
        let previousReplyTarget = replyTarget
        let previousPendingTrade = pendingSharedTrade
        insertSorted(optimistic)
        if let sharedTrade {
            sharedTrades[sharedTrade.id] = sharedTrade
        }
        draft = ""
        pendingSharedTrade = nil
        replyTarget = nil
        maintainKeyboardScrollAnchor = true
        requestThreadScrollToBottom()
        composerFocusToken = UUID()
        if let rootID = parentID {
            expandedReplyThreads.insert(rootID)
        }
        engagementStore.applyCommentCountDelta(1, on: target)
        ExperienceHaptics.play(.selection)

        if target.id.hasPrefix("dev-") {
            ExperienceHaptics.play(.success)
            return
        }

        do {
            let created = try await repository.addComment(
                body: text,
                parentID: parentID,
                sharedTradeID: capturedSharedTrade?.id,
                on: target
            )
            reconcileCreatedComment(created, replacingOptimisticID: optimisticID)
            likesByCommentID[created.id] = .empty
            if let tradeID = created.sharedTradeID, let cached = sharedTrades[tradeID] {
                sharedTrades[tradeID] = cached
            }
            await hydrateSharedTrades(from: [created])
            restartCommentLikeRealtime(for: comments)
            requestThreadScrollToBottom()
            ExperienceHaptics.play(.success)
        } catch {
            comments = previous
            replyTarget = previousReplyTarget
            pendingSharedTrade = previousPendingTrade
            engagementStore.applyCommentCountDelta(-1, on: target)
            draft = text
            if capturedReplyTarget != nil {
                replyTarget = capturedReplyTarget
            }
            if let capturedSharedTrade {
                pendingSharedTrade = capturedSharedTrade
            }
            errorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    func toggleCommentLike(_ comment: InteractionComment) async {
        guard canLikeComments else { return }
        guard !busyCommentIDs.contains(comment.id) else { return }

        busyCommentIDs.insert(comment.id)
        commentLikeMutationEpoch[comment.id, default: 0] += 1
        let mutationEpoch = commentLikeMutationEpoch[comment.id]!
        defer { busyCommentIDs.remove(comment.id) }

        let previous = likesByCommentID[comment.id] ?? .empty
        let optimistic = previous.togglingLike()
        likesByCommentID[comment.id] = optimistic
        ExperienceHaptics.play(.selection)

        do {
            try await repository.setCommentLiked(optimistic.liked, commentID: comment.id, source: commentLikeSource)
        } catch {
            if commentLikeMutationEpoch[comment.id] == mutationEpoch {
                likesByCommentID[comment.id] = previous
            }
            ExperienceHaptics.play(.warning)
        }
    }

    func toggleCommentPin(_ comment: InteractionComment, pinned: Bool) async {
        guard canPinComment(comment) else { return }
        guard !comment.isReply else { return }
        guard !busyPinCommentIDs.contains(comment.id) else { return }

        busyPinCommentIDs.insert(comment.id)
        defer { busyPinCommentIDs.remove(comment.id) }

        let previous = comments
        comments = CommentPinSemantics.applyPinnedState(comments, commentID: comment.id, pinned: pinned)
        ExperienceHaptics.play(.selection)

        if target.id.hasPrefix("dev-") {
            return
        }

        do {
            try await repository.setCommentPinned(pinned, commentID: comment.id, on: target)
        } catch {
            comments = previous
            ExperienceHaptics.play(.warning)
        }
    }

    func stopCommentRealtime() {
        stopCommentLikeRealtime()
        stopCommentPinRealtime()
    }

    func stopCommentLikeRealtime() {
        commentLikeRealtimeTask?.cancel()
        commentLikeRealtimeTask = nil
        let ids = trackedCommentIDs
        trackedCommentIDs = []
        guard !ids.isEmpty else { return }
        let consumer = commentLikeRealtimeConsumer
        commentLikeRealtimeConsumer = nil
        Task { [realtimeHub, consumer] in
            await realtimeHub?.releaseWatch(consumer)
        }
    }

    func stopCommentPinRealtime() {
        commentPinRealtimeTask?.cancel()
        commentPinRealtimeTask = nil
        guard !target.id.hasPrefix("dev-") else { return }
        let consumer = commentPinRealtimeConsumer
        commentPinRealtimeConsumer = nil
        Task { [realtimeHub, consumer] in
            await realtimeHub?.releaseWatch(consumer)
        }
    }

    /// Architecture-ready, edit UI ships when web exposes body update.
    func beginEdit(_: InteractionComment) {
        // Reserved for Phase 6 follow-up (web pin-only today).
    }

    private func insertSorted(_ comment: InteractionComment) {
        comments.append(comment)
        if sort == .newest {
            comments.sort { $0.createdAt > $1.createdAt }
        } else {
            comments.sort { $0.createdAt < $1.createdAt }
        }
    }

    private func mergeCommentsFromServer(_ loaded: [InteractionComment]) -> [InteractionComment] {
        let pendingOptimistic = comments.filter { $0.id.rawValue.hasPrefix("local-") }
        var merged = loaded
        for optimistic in pendingOptimistic {
            let alreadyPresent = merged.contains { server in
                server.id == optimistic.id
                    || CommentThreadSupport.matchesOptimistic(server, optimistic)
            }
            if !alreadyPresent {
                merged.append(optimistic)
            }
        }
        if sort == .newest {
            merged.sort { $0.createdAt > $1.createdAt }
        } else {
            merged.sort { $0.createdAt < $1.createdAt }
        }
        return merged
    }

    private func reconcileCreatedComment(
        _ created: InteractionComment,
        replacingOptimisticID optimisticID: CommentID
    ) {
        if let index = comments.firstIndex(where: { $0.id == optimisticID }) {
            comments[index] = created
            return
        }
        if let equivalentIndex = comments.firstIndex(where: {
            CommentThreadSupport.matchesOptimistic(created, $0)
        }) {
            comments[equivalentIndex] = created
            return
        }
        if !comments.contains(where: { $0.id == created.id }) {
            insertSorted(created)
        }
    }

    func delete(_ comment: InteractionComment) async {
        let previous = comments
        let previousLikes = likesByCommentID
        let removedIDs = CommentThreadSupport.descendantIDs(of: comment.id, in: comments)
        comments.removeAll { removedIDs.contains($0.id) }
        for id in removedIDs {
            likesByCommentID.removeValue(forKey: id)
        }
        engagementStore.applyCommentCountDelta(-removedIDs.count, on: target)
        restartCommentLikeRealtime(for: comments)

        if target.id.hasPrefix("dev-") {
            ExperienceHaptics.play(.success)
            return
        }

        do {
            try await repository.deleteComment(id: comment.id, on: target)
            ExperienceHaptics.play(.success)
        } catch {
            comments = previous
            likesByCommentID = previousLikes
            engagementStore.replaceCommentCount(previous.count, on: target)
            restartCommentLikeRealtime(for: comments)
            errorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    private func loadCommentLikeMeta(for loaded: [InteractionComment]) async {
        let ids = loaded.map(\.id)
        guard !ids.isEmpty, !target.id.hasPrefix("dev-") else {
            likesByCommentID = [:]
            return
        }
        do {
            likesByCommentID = try await repository.commentLikeMeta(
                for: ids,
                source: commentLikeSource
            )
        } catch {
            var fallback: [CommentID: CommentLikeSnapshot] = [:]
            for id in ids {
                fallback[id] = likesByCommentID[id] ?? .empty
            }
            likesByCommentID = fallback
        }
    }

    private func restartCommentLikeRealtime(for loaded: [InteractionComment]) {
        stopCommentLikeRealtime()
        trackedCommentIDs = loaded.map(\.id.rawValue).filter { !$0.hasPrefix("local-") }
    }

    private func restartCommentPinRealtime() {
        stopCommentPinRealtime()
    }
}
