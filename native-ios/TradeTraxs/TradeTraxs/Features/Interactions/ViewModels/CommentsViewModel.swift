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

    let target: InteractionTarget

    private let repository: any InteractionRepository
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
    private var trackedCommentIDs: [String] = []
    private var busyCommentIDs: Set<CommentID> = []
    private var busyPinCommentIDs: Set<CommentID> = []
    private var viewerUserID: String?

    init(
        target: InteractionTarget,
        repository: any InteractionRepository,
        engagementStore: EngagementStore,
        session: any SessionProviding,
        contentOwnerUserID: String? = nil,
        detailCache: DetailPresentationCache? = nil,
        realtimeHub: RealtimeHub? = nil
    ) {
        self.target = target
        self.repository = repository
        self.engagementStore = engagementStore
        self.session = session
        self.contentOwnerUserID = contentOwnerUserID
        self.detailCache = detailCache
        self.realtimeHub = realtimeHub
        self.commentLikeSource = CommentLikeSource.from(target.kind)
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

    func replies(to parentID: CommentID) -> [InteractionComment] {
        comments.filter { $0.parentCommentID == parentID }
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
                comments = loaded
                hasLoaded = true
                engagementStore.replaceCommentCount(loaded.count, on: target)
                await loadCommentLikeMeta(for: loaded)
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
        guard !text.isEmpty, !isPosting else { return }
        isPosting = true
        defer { isPosting = false }

        let userID = await session.currentUserID.map { ProfileID($0.rawValue) }
            ?? ProfileID("dev.local")
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
            parentCommentID: nil,
            createdAt: Date(),
            isPinned: false
        )
        let previous = comments
        insertSorted(optimistic)
        draft = ""
        engagementStore.applyCommentCountDelta(1, on: target)
        ExperienceHaptics.play(.selection)

        if target.id.hasPrefix("dev-") {
            ExperienceHaptics.play(.success)
            return
        }

        do {
            let created = try await repository.addComment(body: text, parentID: nil, on: target)
            if let index = comments.firstIndex(where: { $0.id == optimisticID }) {
                comments[index] = created
            } else {
                insertSorted(created)
            }
            likesByCommentID[created.id] = .empty
            restartCommentLikeRealtime(for: comments)
            ExperienceHaptics.play(.success)
        } catch {
            comments = previous
            engagementStore.applyCommentCountDelta(-1, on: target)
            draft = text
            errorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    func toggleCommentLike(_ comment: InteractionComment) async {
        guard canLikeComments else { return }
        guard !busyCommentIDs.contains(comment.id) else { return }

        busyCommentIDs.insert(comment.id)
        defer { busyCommentIDs.remove(comment.id) }

        let previous = likesByCommentID[comment.id] ?? .empty
        let optimistic = previous.togglingLike()
        likesByCommentID[comment.id] = optimistic
        ExperienceHaptics.play(.selection)

        do {
            try await repository.setCommentLiked(optimistic.liked, commentID: comment.id, source: commentLikeSource)
        } catch {
            likesByCommentID[comment.id] = previous
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
        Task { [commentLikeSource, realtimeHub] in
            await realtimeHub?.stopWatchingCommentLikes(source: commentLikeSource, commentIDs: ids)
        }
    }

    func stopCommentPinRealtime() {
        commentPinRealtimeTask?.cancel()
        commentPinRealtimeTask = nil
        guard !target.id.hasPrefix("dev-") else { return }
        Task { [target, realtimeHub] in
            await realtimeHub?.stopWatchingCommentPinUpdates(target: target)
        }
    }

    /// Architecture-ready — edit UI ships when web exposes body update.
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

    func delete(_ comment: InteractionComment) async {
        let previous = comments
        let previousLikes = likesByCommentID
        let removedIDs = Set(
            comments
                .filter { $0.id == comment.id || $0.parentCommentID == comment.id }
                .map(\.id)
        )
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
        guard let realtimeHub else { return }
        let ids = loaded.map(\.id.rawValue).filter { !$0.hasPrefix("local-") }
        guard !ids.isEmpty, !target.id.hasPrefix("dev-") else { return }

        trackedCommentIDs = ids
        commentLikeRealtimeTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchCommentLikes(
                source: commentLikeSource,
                commentIDs: ids,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                applyCommentLikeRealtime(signal)
            }
        }
    }

    private func restartCommentPinRealtime() {
        stopCommentPinRealtime()
        guard let realtimeHub else { return }
        guard !target.id.hasPrefix("dev-") else { return }

        commentPinRealtimeTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchCommentPinUpdates(
                target: target,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                applyCommentPinRealtime(signal)
            }
        }
    }

    private func applyCommentPinRealtime(_ signal: CommentPinRealtimeSignal) {
        let commentID = CommentID(signal.commentID)
        guard comments.contains(where: { $0.id == commentID }) else { return }
        guard !busyPinCommentIDs.contains(commentID) else { return }
        comments = CommentPinSemantics.applyPinnedState(
            comments,
            commentID: commentID,
            pinned: signal.pinned
        )
    }

    private func applyCommentLikeRealtime(_ signal: CommentLikeRealtimeSignal) {
        guard signal.commentSource == commentLikeSource.rawValue else { return }
        let commentID = CommentID(signal.commentID)
        guard comments.contains(where: { $0.id == commentID }) else { return }
        guard !busyCommentIDs.contains(commentID) else { return }

        let previous = likesByCommentID[commentID] ?? .empty
        likesByCommentID[commentID] = CommentLikeSemantics.applyRealtimeEvent(
            previous,
            event: signal.kind,
            actorUserID: signal.userID,
            currentUserID: viewerUserID
        )
    }
}
