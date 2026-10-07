import Foundation
import Observation
import OSLog
import UIKit

@Observable
@MainActor
final class ConversationViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let conversationID: ConversationID

    private(set) var phase: Phase = .idle
    private(set) var conversation: Conversation?
    private(set) var messages: [Message] = []
    private(set) var sendStates: [MessageID: ConversationBubbleItem.SendState] = [:]
    private(set) var isLoadingOlder = false
    private(set) var hasMoreOlder = true
    private(set) var viewerID: ProfileID?
    private(set) var peerProfile: Profile?
    private(set) var title: String = "Conversation"
    private(set) var subtitle: String?
    var draft = ""
    var isSending = false
    /// Remote image URL already stored for an optimistic message, so retry does not upload again.
    private var uploadedOutboundImageURLs: [MessageID: String] = [:]
    var showsTradePicker = false
    var deleteErrorMessage: String?
    var isSelectionMode = false
    var selectedMessageIDs: Set<MessageID> = []
    var showsBatchDeleteConfirmation = false
    var showsDeleteConversationConfirmation = false
    var isDeletingConversation = false
    var deleteConversationErrorMessage: String?
    private(set) var shouldDismissAfterConversationDelete = false
    private(set) var blockStatus: DmBlockStatus?
    private(set) var isUpdatingBlock = false
    var showsBlockConfirmation = false
    var pendingBlockAction: Bool?
    private(set) var tradePickerSummaries: [TradeSummary] = []
    var tradePickerTrades: [Trade] {
        tradePickerSummaries.map { TradeSummaryMapper.previewTrade(from: $0) }
    }
    private(set) var isLoadingTradePicker = false
    private(set) var sharedTrades: [TradeID: Trade] = [:]
    private(set) var sharedPosts: [PostID: Post] = [:]
    private(set) var sharedReels: [ReelID: Reel] = [:]
    private(set) var sharedAchievements: [AchievementID: Achievement] = [:]
    private(set) var unavailableSharedContentKeys: Set<String> = []
    let scrollCoordinator = ConversationScrollCoordinator()

    typealias InitialScrollPhase = ConversationThreadInitialScrollPhase

    private(set) var initialScrollPhase: InitialScrollPhase = .pending
    private(set) var richContentHydrationCount = 0

    var isInitialScrollConfirmed: Bool { initialScrollPhase == .confirmed }

    /// True while the one-time open bottom pin is active (positioning or layout settling).
    var isInitialScrollPinningBottom: Bool {
        initialScrollPhase == .positioning || initialScrollPhase == .settling
    }

    /// Structured share hydration can resize the newest bubble after first layout.
    var hasPendingRichContentLayout: Bool {
        ConversationThreadScrollSupport.hasPendingRichContentLayout(
            messages: messages,
            richContentHydrationCount: richContentHydrationCount,
            unavailableKeys: unavailableSharedContentKeys,
            isPresentationResolved: { isSharedContentPresentationResolved($0) }
        )
    }

    private let messagesRepo: any MessageRepository
    private let profiles: any ProfileRepository
    private let notifications: (any NotificationRepository)?
    private let tradesRepo: (any TradeRepository)?
    private let feedRepo: (any FeedRepository)?
    private let achievementsRepo: (any AchievementRepository)?
    private let session: any SessionProviding
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let realtimeHub: RealtimeHub?
    private let rpc: (any RPCClient)?

    private var nextOlderCursor: String?
    private var realtimeTask: Task<Void, Never>?
    private var conversationRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var isConversationRealtimeActive = false
    private var loadTask: Task<Void, Never>?
    private var isApplyingRealtime = false
    private var didMarkReadThisOpen = false
    private var loadGeneration: UInt64 = 0
    private var bootstrapMarkReadApplied = false
    /// Soft-deleted / locally removed rows — excluded from merge/realtime reconciliation.
    private var suppressedMessageIDs: Set<MessageID> = []
    private var reactionBusyKeys: Set<String> = []
    private var outboundSharedContentObserver: NSObjectProtocol?
    private var sharedContentHydrationTask: Task<Void, Never>?
    private var sharedContentHydrationBacklog: [Message] = []

    init(
        conversationID: ConversationID,
        messages: any MessageRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        detailCache: DetailPresentationCache,
        trades: (any TradeRepository)? = nil,
        feed: (any FeedRepository)? = nil,
        achievements: (any AchievementRepository)? = nil,
        notifications: (any NotificationRepository)? = nil,
        realtimeHub: RealtimeHub? = nil,
        inboxStore: MessagesInboxStore? = nil,
        rpc: (any RPCClient)? = nil
    ) {
        self.conversationID = conversationID
        self.messagesRepo = messages
        self.profiles = profiles
        self.notifications = notifications
        self.tradesRepo = trades
        self.feedRepo = feed
        self.achievementsRepo = achievements
        self.session = session
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.detailCache = detailCache
        self.realtimeHub = realtimeHub
        self.inboxStore = inboxStore ?? .shared
        self.rpc = rpc
#if DEBUG
        SafeInboxLog.storeObserved(instance: self.inboxStore.debugInstance, source: "ConversationViewModel")
#endif
        applyImmediateOpeningPresentation()
    }

    var timeline: [ConversationTimelineItem] {
        buildTimeline(from: messages)
    }

    func bubbleItem(for messageID: MessageID) -> ConversationBubbleItem? {
        for item in timeline {
            if case .message(let bubble) = item, bubble.id == messageID {
                return bubble
            }
        }
        return nil
    }

    var showsEmpty: Bool {
        phase == .loaded && messages.isEmpty
    }

    var showsDirectMessageActions: Bool {
        guard let conversation else { return false }
        return !conversation.isGroup
    }

    var isMuted: Bool {
        inboxStore.isMuted(conversationID)
    }

    var isMessagingBlocked: Bool {
        blockStatus?.isMessagingBlocked == true
    }

    var canReact: Bool {
        !isMessagingBlocked
            && !isSelectionMode
            && viewerID != nil
            && (phase == .loaded || !messages.isEmpty)
    }

    var blockedByMe: Bool {
        blockStatus?.blockedByMe == true
    }

    var blockConfirmationTitle: String {
        let username = peerProfile?.username ?? conversation?.peerUsername ?? "this user"
        if pendingBlockAction == false {
            return "Unblock @\(username)?"
        }
        return "Block @\(username)?"
    }

    var blockConfirmationMessage: String {
        if pendingBlockAction == false {
            return "They'll be able to message you again and their content will reappear where applicable."
        }
        return "They won't be able to message or interact with you and their content will be hidden where applicable."
    }

    var selectionToolbarTitle: String {
        let count = selectedMessageIDs.count
        return count == 0 ? "Select Messages" : "\(count) Selected"
    }

    var selectedDeletableMessages: [ConversationBubbleItem] {
        selectedMessageBubbles.filter(canDeleteMessage)
    }

    var batchDeleteConfirmationTitle: String {
        let count = selectedDeletableMessages.count
        return "Delete \(count) Message\(count == 1 ? "" : "s")?"
    }

    var peerProfileID: ProfileID? {
        if let peerProfile { return peerProfile.id }
        guard let viewerID, let conversation else { return nil }
        return MessagesInboxSupport.peerID(in: conversation, viewerID: viewerID)
    }

    var newestMessageID: MessageID? {
        messages.last?.id
    }

#if DEBUG
    func testing_seedOpenThread(
        messages: [Message],
        viewerID: ProfileID = ProfileID("viewer"),
        hasMoreOlder: Bool = true,
        cursor: String? = "cursor"
    ) {
        self.viewerID = viewerID
        self.messages = messages
        phase = .loaded
        self.hasMoreOlder = hasMoreOlder
        nextOlderCursor = cursor
    }
#endif

    func loadIfNeeded() {
        guard loadTask == nil else { return }
        loadTask = Task { await performInitialLoad() }
    }

    func retryLoad() {
        guard loadTask == nil else { return }
        phase = .idle
        loadTask = Task { await performInitialLoad(forceNetwork: true) }
    }

    func refreshNewest() async {
        await fetchIncrementalUpdates()
    }

    func beginPagination(anchorMessageID: MessageID) {
        guard isInitialScrollConfirmed else { return }
        scrollCoordinator.beginPagination(
            anchorMessageID: anchorMessageID,
            conversationID: conversationID
        )
    }

    func resetInitialScrollPhase() {
        initialScrollPhase = .pending
    }

    func beginInitialScrollPositioning() {
        guard initialScrollPhase == .pending, !messages.isEmpty else { return }
        initialScrollPhase = .positioning
#if DEBUG
        ConversationScrollDiagnostics.logInitialScrollPhase(
            "positioning",
            conversationID: conversationID,
            messageCount: messages.count,
            newestMessageID: newestMessageID
        )
#endif
    }

    func beginInitialScrollSettling() {
        guard initialScrollPhase == .positioning else { return }
        initialScrollPhase = .settling
#if DEBUG
        ConversationScrollDiagnostics.logInitialScrollPhase(
            "settling",
            conversationID: conversationID,
            messageCount: messages.count,
            newestMessageID: newestMessageID,
            pendingRichLayout: hasPendingRichContentLayout
        )
#endif
    }

    func confirmInitialScrollPosition(userInitiatedRelease: Bool = false) {
        guard initialScrollPhase == .positioning || initialScrollPhase == .settling else { return }
        initialScrollPhase = .confirmed
        scrollCoordinator.completeInitialScrollPosition(conversationID: conversationID)
#if DEBUG
        ConversationScrollDiagnostics.logInitialScrollPhase(
            userInitiatedRelease ? "confirmed-user-release" : "confirmed",
            conversationID: conversationID,
            messageCount: messages.count,
            newestMessageID: newestMessageID,
            pendingRichLayout: hasPendingRichContentLayout
        )
#endif
    }

    func confirmInitialScrollPositionForEmptyThread() {
        guard messages.isEmpty, phase == .loaded else { return }
        initialScrollPhase = .confirmed
        scrollCoordinator.completeInitialScrollPosition(conversationID: conversationID)
    }

    func loadOlderIfNeeded() async {
        guard isInitialScrollConfirmed else {
#if DEBUG
            ConversationScrollDiagnostics.logPaginationBlocked(reason: "initial-scroll-not-confirmed")
#endif
            return
        }
        guard hasMoreOlder, !isLoadingOlder, phase == .loaded else { return }
        guard let viewerID, !ConversationThreadSupport.isLocalDevelopment(viewerID) else {
            hasMoreOlder = false
            return
        }
        if let anchor = messages.first?.id {
            beginPagination(anchorMessageID: anchor)
        }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            if BackendV2FeatureFlags.isEnabled(.messageThreads), let rpc {
                let result = try await ConversationThreadBootstrapLoader.load(
                    viewerID: viewerID,
                    conversationID: conversationID,
                    cursor: nextOlderCursor,
                    markRead: false,
                    intent: .pagination,
                    rpc: rpc,
                    detailCache: detailCache,
                    inboxStore: inboxStore,
                    loadGeneration: loadGeneration,
                    currentGeneration: { self.loadGeneration },
                    forceNetwork: true
                )
                applyBootstrapApplied(result.applied, isPagination: true)
                nextOlderCursor = result.applied.nextCursor
                hasMoreOlder = result.applied.hasMoreMessages
                hydrateSharedContent(from: result.applied.messages)
            } else {
                var page = PageRequest(limit: 40)
                page.cursor = nextOlderCursor
                let result = try await messagesRepo.messages(in: conversationID, page: page)
                commitMessages(result.items)
                nextOlderCursor = result.nextCursor
                hasMoreOlder = result.nextCursor != nil
            }
        } catch {
            // Soft-fail older page.
        }
    }

    func startRealtime() {
        guard realtimeHub != nil else { return }
        if isConversationRealtimeActive, conversationRealtimeConsumer != nil, realtimeTask != nil {
            MessageRealtimeLog.subscribed(conversationID: conversationID, reason: "already-active")
            return
        }
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
#if DEBUG
            ConversationOpenTrace.realtimeRetain(conversationID: conversationID.rawValue)
#endif
            if let previous = conversationRealtimeConsumer {
                MessageRealtimeLog.unsubscribed(
                    conversationID: conversationID,
                    reason: "replace-before-resubscribe"
                )
                await realtimeHub?.releaseWatch(previous)
                conversationRealtimeConsumer = nil
            }
            // Register topic + join web-equivalent messages postgres_changes. Remain idle — no polling.
            let channel = RealtimeChannelID(
                kind: .conversation,
                topic: conversationID.rawValue
            )
            try? await realtimeHub?.subscriptions.subscribe(channel)
            let token = await session.accessToken
            guard let realtimeHub else { return }
            let watch = realtimeHub.watchConversationMessages(
                conversationID: conversationID,
                accessToken: token,
                debugOwner: "ConversationThread"
            )
            conversationRealtimeConsumer = watch.consumer
            isConversationRealtimeActive = true
            MessageRealtimeLog.subscribed(conversationID: conversationID, reason: "thread-joined")
#if DEBUG
            ConversationOpenTrace.realtimeJoined(conversationID: conversationID.rawValue)
#endif
            SocialRealtimeRepairSurfaces.shared.repairOpenConversation = { [weak self] in
                await self?.repairMissedMessagesAfterReconnect()
            }
            for await signal in watch.events {
                guard !Task.isCancelled else { break }
                await applyRealtimeSignal(signal)
            }
            isConversationRealtimeActive = false
        }
    }

    func stopRealtime() {
        MessageRealtimeLog.unsubscribed(conversationID: conversationID, reason: "conversation-disappear")
        syncThreadSessionCache(context: "leave")
        VoiceMessagePlaybackController.shared.stopAll()
        stopOutboundSharedContentObserver()
        realtimeTask?.cancel()
        realtimeTask = nil
        isConversationRealtimeActive = false
        if inboxStore.activeConversationID == conversationID {
            inboxStore.setActiveConversation(nil)
        }
        if SocialRealtimeRepairSurfaces.shared.repairOpenConversation != nil {
            SocialRealtimeRepairSurfaces.shared.repairOpenConversation = nil
        }
        let consumer = conversationRealtimeConsumer
        conversationRealtimeConsumer = nil
        Task { [conversationID, realtimeHub, consumer] in
            let channel = RealtimeChannelID(
                kind: .conversation,
                topic: conversationID.rawValue
            )
            try? await realtimeHub?.subscriptions.unsubscribe(channel)
            await realtimeHub?.releaseWatch(consumer)
        }
    }

    func sendText() async {
        guard !rejectGuestMutationIfNeeded() else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        await send(body: text, imageURL: nil, localImageData: nil)
    }

    func sendImage(_ image: UIImage) async {
        guard !rejectGuestMutationIfNeeded() else { return }
        guard !isMessagingBlocked else { return }
        guard let data = MediaImagePreparation.chatJPEGData(from: image) else { return }
        await send(body: draft.trimmingCharacters(in: .whitespacesAndNewlines), imageURL: nil, localImageData: data)
        draft = ""
    }

    func sendVoice(localFileURL: URL, duration: TimeInterval) async {
        defer { try? FileManager.default.removeItem(at: localFileURL) }
        guard !rejectGuestMutationIfNeeded() else { return }
        guard !isSending else { return }
        guard let data = try? Data(contentsOf: localFileURL) else { return }
        await sendVoice(data: data, duration: duration)
    }

    func presentTradePicker() {
        ExperienceHaptics.play(.selection)
        showsTradePicker = true
    }

    func loadTradePickerIfNeeded() async {
        guard tradePickerSummaries.isEmpty, !isLoadingTradePicker else { return }
        guard let viewerID, let tradesRepo else { return }
        isLoadingTradePicker = true
        defer { isLoadingTradePicker = false }
        if ConversationThreadSupport.isLocalDevelopment(viewerID) {
            tradePickerSummaries = TradeShareFixtures.sampleTrades(ownerID: viewerID).map {
                TradeSummaryMapper.summary(fromPartialListTrade: $0)
            }
            return
        }
        do {
            let page = try await tradesRepo.trades(
                ownedBy: viewerID,
                accountID: nil,
                page: PageRequest(limit: 40),
                publicOnly: false
            )
            tradePickerSummaries = page.items.map { TradeSummaryMapper.summary(fromPartialListTrade: $0) }
        } catch {
            tradePickerSummaries = []
        }
    }

    func sendTrade(_ trade: Trade) async {
        guard !rejectGuestMutationIfNeeded() else { return }
        guard viewerID != nil, !isSending else { return }
        let summary =
            tradePickerSummaries.first(where: { $0.id == trade.id })
            ?? TradeSummaryMapper.summary(fromPartialListTrade: trade)
        await sendTradeSummary(summary)
    }

    func sendTradeSummary(_ summary: TradeSummary) async {
        guard !rejectGuestMutationIfNeeded() else { return }
        guard let viewerID, !isSending else { return }
        showsTradePicker = false
        sharedTrades[summary.id] = TradeSummaryMapper.previewTrade(from: summary)
        detailCache.seedPresentationSeed(summary)
        isSending = true
        defer { isSending = false }

        let tempID = MessageID("temp-\(UUID().uuidString)")
        let optimistic = Message(
            id: tempID,
            conversationID: conversationID,
            senderProfileID: viewerID,
            kind: .tradeShare,
            body: nil,
            attachments: [
                MessageAttachment(
                    id: summary.id.rawValue,
                    media: MediaReference(id: summary.id.rawValue, kind: .file, altText: "Shared trade"),
                    tradeID: summary.id
                ),
            ],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        commitMessages([optimistic])
        sendStates[tempID] = .sending
        scrollCoordinator.handle(
            .outgoingMessageInserted(messageID: tempID),
            conversationID: conversationID
        )

        if ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversationID)
        {
            sendStates[tempID] = .sent
            patchInbox(with: optimistic, source: "devSend")
            return
        }

        do {
            let saved = try await messagesRepo.send(optimistic)
            scrollCoordinator.handle(
                .optimisticConfirmed(from: tempID, to: saved.id),
                conversationID: conversationID
            )
            commitMessages([saved], recordScrollEvents: false)
            sendStates.removeValue(forKey: tempID)
            sendStates[saved.id] = .sent
            sharedTrades[summary.id] = TradeSummaryMapper.previewTrade(from: summary)
            patchInbox(with: saved, source: "confirmedTradeSend")
            SafeInboxLog.sendCompleted(
                conversationID: saved.conversationID,
                messageID: saved.id,
                bodyChars: 0,
                hasAttachment: true
            )
            ExperienceHaptics.play(.messageSent)
        } catch {
            sendStates[tempID] = .failed
            ExperienceHaptics.play(.error)
        }
    }

    func sharedTrade(for message: Message) -> Trade? {
        if let tradeID = message.attachments.first?.tradeID {
            return sharedTrades[tradeID]
        }
        if case .trade(let tradeID) = message.sharedContent {
            return sharedTrades[tradeID]
        }
        if let post = sharedPost(for: message), let tradeID = post.linkedTradeID {
            return sharedTrades[tradeID]
        }
        return nil
    }

    func sharedPost(for message: Message) -> Post? {
        guard let reference = message.sharedContent else { return nil }
        switch reference {
        case .feedPost(let id), .profilePost(let id):
            return sharedPosts[id]
        default:
            return nil
        }
    }

    func sharedReel(for message: Message) -> Reel? {
        guard case .reel(let id) = message.sharedContent else { return nil }
        return sharedReels[id]
    }

    func sharedAchievement(for message: Message) -> Achievement? {
        guard case .achievementPost(let postReference) = message.sharedContent else { return nil }
        return SharedContentEntityPresentation.resolvedAchievement(
            forPostReference: postReference,
            detailCache: detailCache,
            sharedAchievements: sharedAchievements
        )
    }

    func isSharedContentUnavailable(_ message: Message) -> Bool {
        guard let reference = message.sharedContent else { return false }
        return unavailableSharedContentKeys.contains(reference.stableKey)
    }

    private func isSharedContentPresentationResolved(_ message: Message) -> Bool {
        if message.kind == .tradeShare || message.attachments.first?.tradeID != nil {
            return sharedTrade(for: message) != nil
        }
        if sharedPost(for: message) != nil { return true }
        if sharedReel(for: message) != nil { return true }
        if sharedAchievement(for: message) != nil { return true }
        return false
    }

    func authorProfile(for profileID: ProfileID) -> Profile? {
        detailCache.profile(id: profileID)
    }

    func retry(_ item: ConversationBubbleItem) async {
        guard sendStates[item.id] == .failed else { return }
        sendStates[item.id] = .sending
        let tempID = item.id
        if ConversationMessageMerge.isOptimisticMessageID(tempID),
           let uploadedURL = uploadedOutboundImageURLs[tempID]
        {
            await completeOptimisticSend(
                tempID: tempID,
                body: item.text ?? "",
                imageURL: uploadedURL,
                localImageData: nil
            )
            return
        }
        if ConversationMessageMerge.isOptimisticMessageID(tempID),
           let localData = OptimisticOutboundImageStore.shared.jpegData(for: tempID)
        {
            await resendFailedOptimisticImage(
                tempID: tempID,
                body: item.text ?? "",
                localImageData: localData
            )
            return
        }

        let body = item.text ?? ""
        let remoteImageURL = retryableRemoteImageURL(for: item)
        switch await reconcileOptimisticDirectSend(
            sentAt: item.message.createdAt,
            body: body,
            imageURL: remoteImageURL,
            tradeID: item.message.kind == .tradeShare ? item.message.attachments.first?.tradeID : nil
        ) {
        case .matched(let reconciled):
            commitMessages([reconciled], recordScrollEvents: false)
            sendStates.removeValue(forKey: item.id)
            sendStates[reconciled.id] = .sent
            patchInbox(with: reconciled, source: "reconciledSend")
            return
        case .unavailable:
            sendStates[item.id] = .failed
            return
        case .notOnServer:
            break
        }

        if item.message.kind == .tradeShare, let trade = sharedTrade(for: item.message) {
            removeMessage(id: item.id)
            sendStates.removeValue(forKey: item.id)
            await sendTrade(trade)
            return
        }

        guard remoteImageURL != nil || !body.isEmpty else {
            sendStates[item.id] = .failed
            return
        }
        removeMessage(id: item.id)
        sendStates.removeValue(forKey: item.id)
        await send(body: body, imageURL: remoteImageURL, localImageData: nil)
    }

    private func retryableRemoteImageURL(for item: ConversationBubbleItem) -> String? {
        guard item.message.kind == .media,
              let media = item.imageReference,
              media.kind == .image,
              !OptimisticOutboundImageSupport.isOptimisticMediaID(media.id)
        else { return nil }
        return media.id
    }

    private enum OutboundReconcile {
        case matched(Message)
        case notOnServer
        case unavailable
    }

    /// Confirms a lost response before inserting another row.
    private func reconcileOptimisticDirectSend(
        sentAt: Date,
        body: String,
        imageURL: String?,
        tradeID: TradeID?
    ) async -> OutboundReconcile {
        guard let viewerID else { return .unavailable }
        do {
            let page = try await messagesRepo.messages(
                in: conversationID,
                page: PageRequest(limit: 20)
            )
            if let match = page.items.first(where: { message in
                guard message.senderProfileID == viewerID,
                      abs(message.createdAt.timeIntervalSince(sentAt)) < 45
                else { return false }
                if let tradeID {
                    return message.attachments.contains { $0.tradeID == tradeID }
                }
                if let imageURL {
                    return message.attachments.contains { $0.media.id == imageURL }
                }
                return (message.body ?? "") == body
            }) {
                return .matched(match)
            }
            return .notOnServer
        } catch {
            return .unavailable
        }
    }

    func reactionSummaries(for message: Message) -> [RoomMessageReactionSummary] {
        MessageReactionSemantics.aggregate(message.roomReactions, viewerID: viewerID)
    }

    func reactionConfiguration(for message: Message) -> MessageReactionConfiguration? {
        guard canReact || !message.roomReactions.isEmpty else { return nil }
        let summaries = reactionSummaries(for: message).map(MessageReactionSummary.init)
        return MessageReactionConfiguration(
            summaries: summaries,
            supportedEmojis: MessageReactionSemantics.supportedEmojis,
            isEnabled: canReact,
            onToggle: { [weak self] emoji in
                Task { await self?.toggleReaction(messageID: message.id, emoji: emoji) }
            }
        )
    }

    func toggleReaction(messageID: MessageID, emoji: String) async {
        guard canReact, let viewerID else { return }
        let busyKey = "\(messageID.rawValue)::\(emoji)"
        guard !reactionBusyKeys.contains(busyKey) else { return }
        reactionBusyKeys.insert(busyKey)
        defer { reactionBusyKeys.remove(busyKey) }

        let reactions = messages.first(where: { $0.id == messageID })?.roomReactions ?? []
        let skipNetwork = ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversationID)
        await MessageReactionToggleCoordinator.toggle(
            messageID: messageID,
            emoji: emoji,
            viewerID: viewerID,
            reactions: reactions,
            skipNetwork: skipNetwork,
            patch: { [weak self] id, row, mode in
                self?.patchMessageReaction(messageID: id, row: row, mode: mode)
            },
            insert: { [weak self] optimistic in
                guard let self else { throw AppError.unknown(message: "released") }
                return try await self.messagesRepo.insertMessageReaction(
                    conversationID: self.conversationID,
                    messageID: messageID,
                    userID: optimistic.userID,
                    reaction: optimistic.reaction
                )
            },
            delete: { [weak self] reactionID in
                try await self?.messagesRepo.deleteMessageReaction(id: reactionID)
            }
        )
    }

    func canDeleteMessage(_ item: ConversationBubbleItem) -> Bool {
        guard item.isOutgoing else { return false }
        guard item.message.kind != .system else { return false }
        if item.sendState == .failed { return true }
        guard item.sendState == .sent else { return false }
        guard !ConversationMessageMerge.isOptimisticMessageID(item.message.id) else { return false }
        return true
    }

    func deleteMessage(_ item: ConversationBubbleItem) async {
        await deleteMessages([item])
    }

    func enterSelectionMode() {
        isSelectionMode = true
        selectedMessageIDs = []
    }

    func cancelSelectionMode() {
        isSelectionMode = false
        selectedMessageIDs = []
        showsBatchDeleteConfirmation = false
    }

    func toggleMessageSelection(_ messageID: MessageID) {
        if selectedMessageIDs.contains(messageID) {
            selectedMessageIDs.remove(messageID)
        } else {
            selectedMessageIDs.insert(messageID)
        }
    }

    func isMessageSelected(_ messageID: MessageID) -> Bool {
        selectedMessageIDs.contains(messageID)
    }

    func requestDeleteSelectedMessages() {
        guard !selectedDeletableMessages.isEmpty else { return }
        ExperienceHaptics.play(.warning)
        showsBatchDeleteConfirmation = true
    }

    func confirmDeleteSelectedMessages() async {
        showsBatchDeleteConfirmation = false
        let items = selectedDeletableMessages
        guard !items.isEmpty else { return }
        await deleteMessages(items)
        cancelSelectionMode()
    }

    func toggleMute() {
        ExperienceHaptics.play(.selection)
        Task { await setConversationMuted(muted: !isMuted) }
    }

    func requestBlockToggle() {
        pendingBlockAction = !blockedByMe
        showsBlockConfirmation = true
    }

    func confirmBlockToggle() async {
        showsBlockConfirmation = false
        guard let shouldBlock = pendingBlockAction,
              let peerID = peerProfileID
        else { return }
        pendingBlockAction = nil
        guard !isUpdatingBlock else { return }
        isUpdatingBlock = true
        defer { isUpdatingBlock = false }
        do {
            let status = try await UserBlockCoordinator.shared.setBlocked(
                otherID: peerID,
                conversationID: conversationID,
                blocked: shouldBlock,
                peerUsername: peerProfile?.username ?? conversation?.peerUsername,
                messages: messagesRepo,
                inboxStore: inboxStore
            )
            blockStatus = status
            if shouldBlock {
                shouldDismissAfterConversationDelete = true
            }
            ExperienceHaptics.play(.success)
        } catch {
            deleteErrorMessage = UserFacingError.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    func setConversationMuted(muted: Bool) async {
        let previous = isMuted
        guard previous != muted else { return }
        inboxStore.applyConversationMute(conversationID: conversationID, isMuted: muted)
        if var conversation {
            conversation.isMuted = muted
            self.conversation = conversation
        }

        if let viewerID,
           ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversationID)
        {
            return
        }

        do {
            try await messagesRepo.setConversationNotificationsEnabled(
                conversationID: conversationID,
                enabled: !muted
            )
        } catch {
            inboxStore.applyConversationMute(conversationID: conversationID, isMuted: previous)
            if var conversation {
                conversation.isMuted = previous
                self.conversation = conversation
            }
        }
    }

    func requestDeleteConversation() {
        guard !isDeletingConversation else { return }
        ExperienceHaptics.play(.warning)
        showsDeleteConversationConfirmation = true
    }

    func confirmDeleteConversation() async {
        guard !isDeletingConversation else { return }
        isDeletingConversation = true
        deleteConversationErrorMessage = nil
        showsDeleteConversationConfirmation = false
        defer { isDeletingConversation = false }

        if let viewerID,
           ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversationID)
        {
            inboxStore.removeConversation(id: conversationID)
            shouldDismissAfterConversationDelete = true
            return
        }

        let snapshot = inboxStore.conversations.first { $0.id == conversationID }
        inboxStore.removeConversation(id: conversationID, pendingRemoteDelete: true)

        do {
            try await messagesRepo.deleteConversation(id: conversationID)
            inboxStore.finalizeConversationDelete(id: conversationID)
            if let viewerID {
                ConversationThreadSessionStore.shared.invalidate(
                    viewerID: viewerID,
                    conversationID: conversationID
                )
            }
            shouldDismissAfterConversationDelete = true
            ExperienceHaptics.play(.success)
        } catch {
            if let snapshot {
                inboxStore.restoreRemovedConversation(snapshot)
            } else {
                inboxStore.cancelPendingConversationDelete(id: conversationID)
            }
            deleteConversationErrorMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    private var selectedMessageBubbles: [ConversationBubbleItem] {
        timeline.compactMap { item in
            guard case .message(let bubble) = item else { return nil }
            guard selectedMessageIDs.contains(bubble.id) else { return nil }
            return bubble
        }
    }

    private func deleteMessages(_ items: [ConversationBubbleItem]) async {
        guard !items.isEmpty else { return }
        deleteErrorMessage = nil

        var remoteSnapshots: [Message] = []
        for item in items {
            guard canDeleteMessage(item) else { continue }
            if item.sendState == .failed {
                removeMessage(id: item.id)
                continue
            }
            if let viewerID,
               ConversationThreadSupport.isLocalDevelopment(viewerID)
                || ConversationThreadSupport.isLocalConversation(conversationID)
            {
                removeMessage(id: item.id)
                continue
            }
            remoteSnapshots.append(item.message)
            removeMessage(id: item.id)
        }

        guard !remoteSnapshots.isEmpty else {
            syncThreadSessionCache(context: "delete.local")
            refreshInboxPreviewAfterDelete()
            return
        }

        var failed: [Message] = []
        await withTaskGroup(of: (Message, Bool).self) { group in
            for message in remoteSnapshots {
                group.addTask { [conversationID, messagesRepo] in
                    do {
                        try await messagesRepo.deleteMessageForEveryone(
                            message.id,
                            in: conversationID
                        )
                        return (message, true)
                    } catch {
                        return (message, false)
                    }
                }
            }
            for await (message, succeeded) in group where !succeeded {
                failed.append(message)
            }
        }

        for message in failed {
            suppressedMessageIDs.remove(message.id)
            commitMessages([message], recordScrollEvents: false)
        }

        if failed.isEmpty {
            ExperienceHaptics.play(.success)
        } else {
            deleteErrorMessage = failed.count == remoteSnapshots.count
                ? ConversationThreadSupport.message(for: AppError.unknown(message: "Could not delete messages."))
                : "Some messages couldn't be deleted."
            ExperienceHaptics.play(.warning)
        }

        syncThreadSessionCache(context: "delete.batch")
#if DEBUG
        ConversationThreadDiagnostics.logBatchDelete(
            requested: remoteSnapshots.count,
            succeeded: remoteSnapshots.count - failed.count
        )
#endif
        if failed.count < remoteSnapshots.count {
            await revalidateNewestWindowIfNeededAfterDelete()
        }
        refreshInboxPreviewAfterDelete()
    }

    // MARK: - Private

    private func performInitialLoad(forceNetwork: Bool = false) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        suppressedMessageIDs.removeAll()
        bootstrapMarkReadApplied = false
        scrollCoordinator.resetForConversation(conversationID)
        initialScrollPhase = .pending

        let unreadBeforeOpen = inboxStore.conversations.first(where: { $0.id == conversationID })?
            .unreadCount ?? 0
        let paintedBeforeLoad = !messages.isEmpty
        if !paintedBeforeLoad {
            phase = .loading
        }
        // Web optimistic clear on open — badge drops before history finishes loading.
        inboxStore.markRead(conversationID: conversationID)
        inboxStore.setActiveConversation(conversationID)

        let current = await session.currentUserID
        let viewer = current.map { ProfileID($0.rawValue) }
        viewerID = viewer
        let demoInbox = viewer.map(DemoExperienceSupport.usesExploreDemoInbox) == true
        if !demoInbox {
            startRealtime()
        }

        do {
            if demoInbox {
                try await loadFromRepository()
            } else if let viewer,
               ConversationThreadSupport.isLocalDevelopment(viewer)
                || ConversationThreadSupport.isLocalConversation(conversationID)
            {
                await loadLocalFixtures(viewerID: viewer)
            } else if BackendV2FeatureFlags.isEnabled(.messageThreads),
                      let viewer
            {
                try await loadFromV2Bootstrap(
                    viewerID: viewer,
                    generation: generation,
                    unreadBeforeOpen: unreadBeforeOpen,
                    forceNetwork: forceNetwork
                )
            } else {
                try await loadFromRepository()
            }
            await markConversationSeenIfNeeded()
            if phase != .loaded {
                phase = .loaded
            }
            startOutboundSharedContentObserver()
        } catch ConversationThreadBootstrapLoader.LoaderError.rpcUnavailable {
            do {
                try await loadFromRepository()
                await markConversationSeenIfNeeded()
                phase = .loaded
                startRealtime()
                startOutboundSharedContentObserver()
            } catch {
                await markConversationSeenIfNeeded()
                phase = .failed(ConversationThreadSupport.message(for: error))
            }
        } catch ConversationThreadBootstrapLoader.LoaderError.staleResponse {
            // Navigation away — keep cached state if already painted.
            if phase == .loading, conversation != nil {
                phase = .loaded
            }
        } catch {
            if conversation != nil, !messages.isEmpty, phase == .loading {
                phase = .loaded
                startRealtime()
            } else {
                await markConversationSeenIfNeeded()
                phase = .failed(ConversationThreadSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    /// Web `markMessageNotificationsRead` on conversation open — `mark_conversation_read` is owned by
    /// ``InboxMarkReadCoordinator`` (legacy) or thread bootstrap RPC (V2).
    private func markConversationSeenIfNeeded() async {
        inboxStore.markRead(conversationID: conversationID)
        guard !didMarkReadThisOpen else { return }
        didMarkReadThisOpen = true

        guard let viewerID,
              !DemoExperienceSupport.usesExploreDemoInbox(viewerID),
              !ConversationThreadSupport.isLocalDevelopment(viewerID),
              !ConversationThreadSupport.isLocalConversation(conversationID)
        else { return }

        if BackendV2FeatureFlags.isEnabled(.messageThreads), bootstrapMarkReadApplied {
            return
        }

        await markMessageNotificationsRead()
        inboxStore.markRead(conversationID: conversationID)
    }

    /// Web `markMessageNotificationsRead` — one bulk update, no inbox page fetch.
    private func markMessageNotificationsRead() async {
        guard let notifications else { return }
        let started = CFAbsoluteTimeGetCurrent()
        let markedLocally = ActivityInboxStore.shared.markMessageNotificationsReadLocally()
        do {
            _ = try await notifications.markMessageNotificationsRead()
            NotificationReadDiagnostics.logBulkMarkRead(
                ids: markedLocally,
                requests: 1,
                dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            )
        } catch {
            // Server authoritative on next Activity bootstrap; DM read state is unaffected.
        }
    }

    private func loadLocalFixtures(viewerID: ProfileID) async {
        if let cached = inboxStore.conversations.first(where: { $0.id == conversationID }) {
            conversation = cached
        } else {
            conversation = Conversation(
                id: conversationID,
                participantProfileIDs: [viewerID],
                title: "Conversation",
                peerUsername: nil,
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: nil,
                lastMessageAt: nil,
                unreadCount: 0,
                isMuted: false,
                updatedAt: .now
            )
        }
        let peerID = MessagesInboxSupport.peerID(in: conversation!, viewerID: viewerID)
            ?? ProfileID("dev.follower.ada")
        if let profile = FollowListFixtures.profile(id: peerID) ?? detailCache.profile(id: peerID) {
            peerProfile = profile
            detailCache.seed(profile)
        }
        applyHeader(from: conversation)
        replaceMessages(
            ConversationThreadFixtures.messages(
                conversationID: conversationID,
                viewerID: viewerID,
                peerID: peerID
            )
        )
        hasMoreOlder = false
    }

    private func loadFromRepository() async throws {
        let meta = try await messagesRepo.conversation(id: conversationID)
        conversation = meta
        if let viewerID {
            let peerID = MessagesInboxSupport.peerID(in: meta, viewerID: viewerID)
            if let peerID {
                if let cached = detailCache.profile(id: peerID) {
                    peerProfile = cached
                } else if let fetched = try? await SessionProfileStore.shared.profiles(
                    ids: [peerID],
                    detailCache: detailCache,
                    repository: profiles
                ).first {
                    peerProfile = fetched
                }
            }
        }
        applyHeader(from: meta)
        let page = try await messagesRepo.messages(
            in: conversationID,
            page: PageRequest(limit: 50)
        )
        replaceMessages(page.items)
        nextOlderCursor = page.nextCursor
        hasMoreOlder = page.nextCursor != nil
        hydrateSharedContent(from: messages)
    }

    private func loadFromV2Bootstrap(
        viewerID: ProfileID,
        generation: UInt64,
        unreadBeforeOpen: Int,
        forceNetwork: Bool
    ) async throws {
        let cacheKey = ConversationThreadSessionStore.cacheKey(
            viewerID: viewerID,
            conversationID: conversationID
        )
        let cached = ConversationThreadSessionStore.shared.restore(key: cacheKey)
        let alreadyPainted = !messages.isEmpty

        MessageSyncLog.conversationOpened(
            conversationID: conversationID,
            localNewestID: ConversationThreadSyncPolicy.localNewestMessageID(in: messages)
        )

        if let cached, !forceNetwork, !alreadyPainted {
#if DEBUG
            ConversationThreadDiagnostics.logCacheReopen(
                messages: cached.messages.count,
                cursor: cached.nextCursor
            )
#endif
            applyBootstrapApplied(
                ConversationThreadBootstrapApplier.Applied(
                    conversation: cached.conversation,
                    messages: cached.messages,
                    nextCursor: cached.nextCursor,
                    hasMoreMessages: cached.hasMoreMessages,
                    markReadApplied: false,
                    notificationsMarkedRead: 0,
                    skippedMessages: 0,
                    blockStatus: nil
                )
            )
            phase = .loaded
#if DEBUG
            ConversationOpenTrace.firstRender(
                conversationID: conversationID.rawValue,
                source: "sessionOrDisk"
            )
#endif
            Task { [weak self] in
                self?.hydrateSharedContent(from: self?.messages ?? [])
            }
            await reconcileInboxAheadIfNeeded(viewerID: viewerID)
            let inboxAhead = ConversationThreadSyncPolicy.isInboxAheadOfThread(
                inbox: inboxStore.conversations.first(where: { $0.id == conversationID }),
                threadMessages: messages
            )
            let needsWindowBackfill = ConversationThreadSessionStore.openThreadNeedsFullBootstrap(
                messageCount: cached.messages.count
            )
            if !cached.isSoftStale, unreadBeforeOpen == 0, !needsWindowBackfill, !inboxAhead {
                logThreadStateDiagnostics(context: "cache.reopen.skip-network")
                return
            }
            scheduleBackgroundThreadBootstrap(
                viewerID: viewerID,
                generation: generation,
                unreadBeforeOpen: unreadBeforeOpen,
                forceNetwork: forceNetwork || inboxAhead,
                cached: cached
            )
            return
        }

        if alreadyPainted, !forceNetwork {
            await reconcileInboxAheadIfNeeded(viewerID: viewerID)
            let inboxAhead = ConversationThreadSyncPolicy.isInboxAheadOfThread(
                inbox: inboxStore.conversations.first(where: { $0.id == conversationID }),
                threadMessages: messages
            )
            let needsWindowBackfill = ConversationThreadSessionStore.openThreadNeedsFullBootstrap(
                messageCount: cached?.messages.count ?? messages.count
            )
            if let cached,
               !cached.isSoftStale,
               unreadBeforeOpen == 0,
               !needsWindowBackfill,
               !inboxAhead
            {
                logThreadStateDiagnostics(context: "cache.immediate.skip-network")
                return
            }
            scheduleBackgroundThreadBootstrap(
                viewerID: viewerID,
                generation: generation,
                unreadBeforeOpen: unreadBeforeOpen,
                forceNetwork: forceNetwork || inboxAhead,
                cached: cached
            )
            return
        }

        try await fetchThreadBootstrapNetwork(
            viewerID: viewerID,
            generation: generation,
            unreadBeforeOpen: unreadBeforeOpen,
            forceNetwork: forceNetwork,
            cached: cached
        )
    }

    private func scheduleBackgroundThreadBootstrap(
        viewerID: ProfileID,
        generation: UInt64,
        unreadBeforeOpen: Int,
        forceNetwork: Bool,
        cached: ConversationThreadSessionStore.Snapshot?
    ) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await fetchThreadBootstrapNetwork(
                    viewerID: viewerID,
                    generation: generation,
                    unreadBeforeOpen: unreadBeforeOpen,
                    forceNetwork: forceNetwork,
                    cached: cached
                )
                await markConversationSeenIfNeeded()
            } catch ConversationThreadBootstrapLoader.LoaderError.staleResponse {
                // Navigation superseded — keep painted thread.
            } catch {
                if messages.isEmpty {
                    phase = .failed(ConversationThreadSupport.message(for: error))
                }
            }
        }
    }

    private func fetchThreadBootstrapNetwork(
        viewerID: ProfileID,
        generation: UInt64,
        unreadBeforeOpen: Int,
        forceNetwork: Bool,
        cached: ConversationThreadSessionStore.Snapshot?
    ) async throws {
        guard let rpc else { throw ConversationThreadBootstrapLoader.LoaderError.flagOff }
#if DEBUG
        ConversationOpenTrace.networkStart(conversationID: conversationID.rawValue)
#endif
        let intent: ConversationThreadBootstrapLoader.LoadIntent = {
            if forceNetwork { return .cacheRevalidation }
            if cached == nil { return .coldOpen }
            if cached?.isSoftStale == true {
                return unreadBeforeOpen > 0 ? .coldOpen : .cacheRevalidation
            }
            return unreadBeforeOpen > 0 ? .coldOpen : .cacheRevalidation
        }()
        let markRead = intent == .coldOpen && !forceNetwork

        let result = try await ConversationThreadBootstrapLoader.load(
            viewerID: viewerID,
            conversationID: conversationID,
            cursor: nil,
            markRead: markRead,
            intent: intent,
            rpc: rpc,
            detailCache: detailCache,
            inboxStore: inboxStore,
            loadGeneration: generation,
            currentGeneration: { self.loadGeneration },
            forceNetwork: forceNetwork
        )

        guard generation == loadGeneration else {
            throw ConversationThreadBootstrapLoader.LoaderError.staleResponse
        }

#if DEBUG
        ConversationOpenTrace.networkEnd(
            conversationID: conversationID.rawValue,
            count: result.applied.messages.count
        )
        ConversationThreadDiagnostics.logOpenPipeline(
            conversationID: conversationID.rawValue,
            stage: "network.bootstrap",
            remoteReturned: result.applied.messages.count,
            requestedPageSize: ConversationThreadSessionStore.messageLimit,
            cursor: result.applied.nextCursor,
            grdbOrDiskStored: nil,
            grdbOrDiskQueried: nil,
            viewModelCount: messages.count,
            renderedCount: nil,
            hasMoreOlder: result.applied.hasMoreMessages
        )
#endif

        if result.cacheHit {
            applyBootstrapApplied(result.applied)
            Task { [weak self] in
                self?.hydrateSharedContent(from: result.applied.messages)
            }
            return
        }

        applyBootstrapApplied(result.applied)
        bootstrapMarkReadApplied = result.applied.markReadApplied
        Task { [weak self] in
            self?.hydrateSharedContent(from: result.applied.messages)
        }
    }

    /// Inbox row + session/disk thread snapshot before the first async load task runs.
    private func applyImmediateOpeningPresentation() {
        if let inboxRow = inboxStore.conversations.first(where: { $0.id == conversationID }) {
            conversation = inboxRow
            applyHeader(from: inboxRow)
        }
        guard let viewerID = inboxStore.persistedViewerID else { return }
        self.viewerID = viewerID
        let cacheKey = ConversationThreadSessionStore.cacheKey(
            viewerID: viewerID,
            conversationID: conversationID
        )
#if DEBUG
        ConversationOpenTrace.diskStart(conversationID: conversationID.rawValue)
#endif
        guard let cached = ConversationThreadSessionStore.shared.restore(key: cacheKey) else { return }
#if DEBUG
        ConversationOpenTrace.diskEnd(
            conversationID: conversationID.rawValue,
            count: cached.messages.count
        )
#endif
        applyBootstrapApplied(
            ConversationThreadBootstrapApplier.Applied(
                conversation: cached.conversation,
                messages: cached.messages,
                nextCursor: cached.nextCursor,
                hasMoreMessages: cached.hasMoreMessages,
                markReadApplied: false,
                notificationsMarkedRead: 0,
                skippedMessages: 0,
                blockStatus: nil
            )
        )
        phase = .loaded
#if DEBUG
        let sorted = ConversationMessageMerge.sortByCreatedAt(cached.messages)
        ConversationThreadDiagnostics.logOpenPipeline(
            conversationID: conversationID.rawValue,
            stage: "immediateOpen.grdb",
            remoteReturned: nil,
            requestedPageSize: ConversationThreadSessionStore.messageLimit,
            cursor: cached.nextCursor,
            grdbOrDiskStored: cached.messages.count,
            grdbOrDiskQueried: cached.messages.count,
            viewModelBefore: 0,
            viewModelAfter: messages.count,
            renderedCount: timelineRenderedMessageCount,
            hasMoreOlder: hasMoreOlder,
            oldestMessageID: sorted.first?.id.rawValue,
            newestMessageID: sorted.last?.id.rawValue,
            initialScrollPhase: String(describing: initialScrollPhase),
            remoteMessageIDsSample: Self.messageIDSample(sorted)
        )
        ConversationOpenTrace.firstRender(
            conversationID: conversationID.rawValue,
            source: "immediateOpen"
        )
#endif
    }

    private func applyBootstrapApplied(
        _ applied: ConversationThreadBootstrapApplier.Applied,
        isPagination: Bool = false
    ) {
        conversation = applied.conversation
        if let viewerID {
            let peerID = MessagesInboxSupport.peerID(in: applied.conversation, viewerID: viewerID)
            if let peerID, let profile = detailCache.profile(id: peerID) {
                peerProfile = profile
            }
        }
        applyHeader(from: applied.conversation)
        if let status = applied.blockStatus {
            blockStatus = status
            if peerProfileID != nil {
                UserBlockCoordinator.shared.cacheStatus(status)
            }
        }
        if isPagination {
            commitMessages(applied.messages, recordScrollEvents: false)
            scrollCoordinator.handle(
                .paginationApplied,
                conversationID: conversationID
            )
        } else {
            applyBootstrapMessages(applied.messages)
            notifyScrollContentApplied(source: .bootstrapApplied)
        }
        nextOlderCursor = applied.nextCursor
        hasMoreOlder = applied.hasMoreMessages
        if ConversationThreadSessionStore.openThreadNeedsFullBootstrap(messageCount: messages.count) {
            hasMoreOlder = true
        }
    }

    /// Web `mergeMessageLists(wire, existing)` — bootstrap must not wipe newer local rows.
    private func applyBootstrapMessages(_ incoming: [Message]) {
        let beforeCount = messages.count
        let beforeOldest = messages.first?.id.rawValue
        let beforeNewest = messages.last?.id.rawValue
        let reconciled = ConversationMessageMerge.reconcileServerFirstPage(
            existing: messages,
            incoming: incoming
        )
        let filtered = filterSuppressed(reconciled)
        if beforeCount > 0, filtered.isEmpty {
#if DEBUG
            ConversationThreadDiagnostics.logOpenPipeline(
                conversationID: conversationID.rawValue,
                stage: "bootstrap.merge.rejected-empty",
                remoteReturned: incoming.count,
                requestedPageSize: ConversationThreadSessionStore.messageLimit,
                cursor: nextOlderCursor,
                grdbOrDiskStored: nil,
                grdbOrDiskQueried: nil,
                viewModelBefore: beforeCount,
                viewModelAfter: beforeCount,
                renderedCount: timelineRenderedMessageCount,
                hasMoreOlder: hasMoreOlder,
                oldestMessageID: beforeOldest,
                newestMessageID: beforeNewest,
                initialScrollPhase: String(describing: initialScrollPhase),
                remoteMessageIDsSample: Self.messageIDSample(incoming)
            )
#endif
            return
        }
        messages = filtered
#if DEBUG
        let sorted = ConversationMessageMerge.sortByCreatedAt(messages)
        ConversationThreadDiagnostics.logOpenPipeline(
            conversationID: conversationID.rawValue,
            stage: "bootstrap.merge",
            remoteReturned: incoming.count,
            requestedPageSize: ConversationThreadSessionStore.messageLimit,
            cursor: nextOlderCursor,
            grdbOrDiskStored: nil,
            grdbOrDiskQueried: nil,
            viewModelBefore: beforeCount,
            viewModelAfter: messages.count,
            renderedCount: timelineRenderedMessageCount,
            hasMoreOlder: hasMoreOlder,
            oldestMessageID: sorted.first?.id.rawValue,
            newestMessageID: sorted.last?.id.rawValue,
            initialScrollPhase: String(describing: initialScrollPhase),
            remoteMessageIDsSample: Self.messageIDSample(incoming)
        )
#endif
    }

    private var timelineRenderedMessageCount: Int {
        buildTimeline(from: messages).reduce(into: 0) { count, item in
            if case .message = item { count += 1 }
        }
    }

#if DEBUG
    private static func messageIDSample(_ messages: [Message], limit: Int = 5) -> String {
        let ids = ConversationMessageMerge.sortByCreatedAt(messages).suffix(limit).map(\.id.rawValue)
        return ids.isEmpty ? "none" : ids.joined(separator: ",")
    }
#endif

    /// Pull-to-refresh / explicit refresh — not used on a timer.
    private func fetchIncrementalUpdates() async {
        await applyRealtimeSignal(MessageRealtimeSignal(kind: .insert, messageID: nil))
    }

    /// Incremental apply from Realtime — never reloads the whole conversation on V2.
    private func applyRealtimeSignal(_ signal: MessageRealtimeSignal) async {
        if let reaction = signal.reactionEvent {
            applyReactionRealtime(reaction, kind: signal.kind)
            return
        }

        guard let viewerID,
              !ConversationThreadSupport.isLocalDevelopment(viewerID),
              !ConversationThreadSupport.isLocalConversation(conversationID),
              !isApplyingRealtime
        else { return }

        if signal.kind == .delete, let rawID = signal.messageID {
            removeMessage(id: MessageID(rawID))
            syncThreadSessionCache(context: "realtime.delete")
            refreshInboxPreviewAfterDelete()
            return
        }

        if signal.kind == .update, signal.deletedForEveryone, let rawID = signal.messageID {
            removeMessage(id: MessageID(rawID))
            syncThreadSessionCache(context: "realtime.soft-delete")
            refreshInboxPreviewAfterDelete()
            return
        }

        if BackendV2FeatureFlags.isEnabled(.messageThreads) {
            await applyRealtimeSignalV2(signal)
            return
        }

        isApplyingRealtime = true
        defer { isApplyingRealtime = false }
        do {
            let page = try await messagesRepo.messages(
                in: conversationID,
                page: PageRequest(limit: 30)
            )
            commitReconciledPage(page.items)
            hydrateSharedContent(from: page.items)
            if let newest = ConversationMessageMerge.sortByCreatedAt(messages).last {
                patchInbox(with: newest, source: "legacyRealtime")
            }
        } catch {
            // Soft-fail event-driven hydrate.
        }
    }

    /// Bounded merge after Realtime reconnect — one page, ID-deduped (Phase 10F).
    fileprivate func repairMissedMessagesAfterReconnect() async {
        guard viewerID != nil else { return }
        guard !isApplyingRealtime else { return }
        isApplyingRealtime = true
        defer { isApplyingRealtime = false }
        do {
            let page = try await messagesRepo.messages(
                in: conversationID,
                page: PageRequest(limit: 30)
            )
            commitMessages(page.items)
            syncThreadSessionCache(context: "reconnectRepair")
            if let newest = ConversationMessageMerge.sortByCreatedAt(messages).last {
                patchInbox(with: newest, source: "reconnectRepair")
            }
        } catch {
            // Non-destructive — keep cached thread.
        }
    }

    /// V2 — dedupe local confirmed sends; never run legacy inbox refresh waterfall.
    private func applyRealtimeSignalV2(_ signal: MessageRealtimeSignal) async {
        if signal.kind == .update, signal.deletedForEveryone, let rawID = signal.messageID {
            removeMessage(id: MessageID(rawID))
            syncThreadSessionCache(context: "realtimeV2.soft-delete")
            refreshInboxPreviewAfterDelete()
            return
        }

        if signal.kind == .insert, let rawID = signal.messageID {
            let messageID = MessageID(rawID)
            MessageRealtimeLog.insertReceived(conversationID: conversationID, messageID: messageID)
            if messages.contains(where: { $0.id == messageID }) {
                MessageRealtimeLog.dropped(reason: "duplicate-in-thread", messageID: messageID)
#if DEBUG
                MessagingRealtimeDebugLog.messageEchoIgnored(messageID: rawID, source: "thread")
#endif
                if let newest = ConversationMessageMerge.sortByCreatedAt(messages).last {
                    patchInbox(with: newest, source: "realtimeDedupe")
                }
                return
            }
            let claimed = MessagingRealtimeDeliveryCoordinator.claimMessageInsert(
                domain: "dm-thread",
                messageID: rawID,
                conversationID: conversationID.rawValue
            )
            if !claimed {
                MessageRealtimeLog.dropped(reason: "claimed-by-inbox-route", messageID: messageID)
                await hydrateThreadMessageIfMissing(messageID: messageID, source: "realtimeClaimedByInbox")
                return
            }
        }

        guard signal.kind == .insert || signal.kind == .update else { return }

        isApplyingRealtime = true
        defer { isApplyingRealtime = false }

        var merged: Message?
        if let payload = signal.recordPayload {
            merged = MessageRealtimeMerge.dmMessage(
                from: payload,
                conversationID: conversationID,
                viewerID: viewerID
            )
        }
        if merged == nil, let rawID = signal.messageID {
#if DEBUG
            MessagingRealtimeDebugLog.networkFallback(reason: "thread_single_row_hydrate")
#endif
            merged = try? await messagesRepo.message(id: MessageID(rawID), in: conversationID)
        }
        guard let incoming = merged else {
            if signal.kind == .insert, let rawID = signal.messageID {
                MessageRealtimeLog.dropped(reason: "hydrate-failed", messageID: MessageID(rawID))
            }
            return
        }

        commitMessages([incoming])
        syncThreadSessionCache(context: "realtimeV2.merge")
        MessageRealtimeLog.persisted(messageID: incoming.id)
        hydrateSharedContent(from: [incoming])
        inboxStore.patchFromMessage(
            incoming,
            viewerID: viewerID!,
            conversationOpen: true,
            policy: incoming.senderProfileID == viewerID ? .confirmedOutgoing : .canonical,
            fallbackConversation: conversation,
            source: "realtimeV2"
        )
        MessageRealtimeLog.visibleThreadUpdated(messageID: incoming.id)
        MessageSyncLog.realtimeApplied(conversationID: conversationID, messageID: incoming.id)
        MessageSyncLog.visibleThreadUpdated(conversationID: conversationID, messageID: incoming.id)
        MessageRealtimeLog.visibleThreadUpdated(messageID: incoming.id)
#if DEBUG
        MessagingRealtimeDebugLog.threadPatch(
            conversationID: conversationID.rawValue,
            messageID: incoming.id.rawValue
        )
#endif
    }

    /// Lightweight catch-up when inbox summary is ahead of the open thread (preview ≠ GRDB rows).
    private func reconcileInboxAheadIfNeeded(viewerID: ProfileID) async {
        guard let inboxRow = inboxStore.conversations.first(where: { $0.id == conversationID }) else {
            return
        }
        guard ConversationThreadSyncPolicy.isInboxAheadOfThread(
            inbox: inboxRow,
            threadMessages: messages
        ) else {
            return
        }
        MessageSyncLog.reconcileStarted(
            conversationID: conversationID,
            after: ConversationThreadSyncPolicy.localNewestMessageID(in: messages)
        )

        if let headID = inboxRow.lastMessageID,
           !messages.contains(where: { $0.id == headID }),
           let fetched = try? await messagesRepo.message(id: headID, in: conversationID)
        {
            MessageSyncLog.missingMessageReceived(conversationID: conversationID, messageID: fetched.id)
            commitMessages([fetched])
            syncThreadSessionCache(context: "inboxAhead.single")
            ConversationThreadSessionStore.shared.patchMessages(
                viewerID: viewerID,
                conversationID: conversationID,
                incoming: [fetched],
                conversation: inboxRow
            )
            MessageSyncLog.persisted(conversationID: conversationID, messageID: fetched.id)
            MessageSyncLog.visibleThreadUpdated(conversationID: conversationID, messageID: fetched.id)
            hydrateSharedContent(from: [fetched])
            return
        }

        guard let rpc else { return }
        let result = try? await ConversationThreadBootstrapLoader.load(
            viewerID: viewerID,
            conversationID: conversationID,
            cursor: nil,
            markRead: false,
            intent: .cacheRevalidation,
            rpc: rpc,
            detailCache: detailCache,
            inboxStore: inboxStore,
            loadGeneration: loadGeneration,
            currentGeneration: { self.loadGeneration },
            forceNetwork: true
        )
        guard let result, !result.cacheHit else { return }
        applyBootstrapMessages(result.applied.messages)
        syncThreadSessionCache(context: "inboxAhead.bootstrap")
        if let newest = ConversationThreadSyncPolicy.localNewestMessageID(in: messages) {
            MessageSyncLog.visibleThreadUpdated(conversationID: conversationID, messageID: newest)
        }
        hydrateSharedContent(from: result.applied.messages)
    }

    private func hydrateThreadMessageIfMissing(messageID: MessageID, source: String) async {
        guard !messages.contains(where: { $0.id == messageID }) else { return }
        guard let viewerID else { return }
        guard let incoming = try? await messagesRepo.message(id: messageID, in: conversationID) else { return }
        MessageRealtimeLog.insertReceived(conversationID: conversationID, messageID: incoming.id)
        MessageSyncLog.missingMessageReceived(conversationID: conversationID, messageID: incoming.id)
        commitMessages([incoming])
        syncThreadSessionCache(context: source)
        MessageRealtimeLog.persisted(messageID: incoming.id)
        ConversationThreadSessionStore.shared.patchMessages(
            viewerID: viewerID,
            conversationID: conversationID,
            incoming: [incoming],
            conversation: conversation
        )
        MessageSyncLog.persisted(conversationID: conversationID, messageID: incoming.id)
        MessageSyncLog.realtimeApplied(conversationID: conversationID, messageID: incoming.id)
        MessageSyncLog.visibleThreadUpdated(conversationID: conversationID, messageID: incoming.id)
        MessageRealtimeLog.visibleThreadUpdated(messageID: incoming.id)
        hydrateSharedContent(from: [incoming])
    }

    /// Sole write path for thread rows — web `mergeMessages` semantics.
    private func commitMessages(_ incoming: [Message], recordScrollEvents: Bool = true) {
        let previousIDs = Set(messages.map(\.id))
        let previousTempIDs = Set(
            messages
                .map(\.id)
                .filter(ConversationMessageMerge.isOptimisticMessageID)
        )
        messages = ConversationMessageMerge.mergeMessages(
            existing: messages,
            incoming: incoming,
            viewerID: viewerID
        )
        messages = filterSuppressed(messages)
        let remainingIDs = Set(messages.map(\.id))
        for tempID in previousTempIDs where !remainingIDs.contains(tempID) {
            sendStates.removeValue(forKey: tempID)
        }
        syncThreadSessionCache(context: "commit")
        guard recordScrollEvents else { return }
        recordIncomingScrollEvents(incoming: incoming, previousIDs: previousIDs)
    }

    private func recordIncomingScrollEvents(incoming: [Message], previousIDs: Set<MessageID>) {
        for message in incoming {
            guard !previousIDs.contains(message.id) else { continue }
            guard !ConversationMessageMerge.isOptimisticMessageID(message.id) else { continue }
            guard message.senderProfileID != viewerID else { continue }
            scrollCoordinator.handle(
                .incomingMessageInserted(messageID: message.id),
                conversationID: conversationID
            )
        }
    }

    private enum ScrollContentSource {
        case bootstrapApplied
        case cacheApplied
    }

    private func notifyScrollContentApplied(source: ScrollContentSource) {
        let event: ConversationScrollCoordinator.Event = switch source {
        case .bootstrapApplied:
            .bootstrapApplied(newestMessageID: newestMessageID, isEmpty: messages.isEmpty)
        case .cacheApplied:
            .cacheApplied(newestMessageID: newestMessageID, isEmpty: messages.isEmpty)
        }
        scrollCoordinator.handle(event, conversationID: conversationID)
    }

    private func syncThreadSessionCache(context: String) {
        guard BackendV2FeatureFlags.isEnabled(.messageThreads),
              let viewerID,
              let conversation
        else { return }
        ConversationThreadSessionStore.shared.syncOpenThreadState(
            viewerID: viewerID,
            conversationID: conversationID,
            conversation: conversation,
            messages: messages,
            nextCursor: nextOlderCursor,
            hasMoreMessages: hasMoreOlder
        )
        logThreadStateDiagnostics(context: context)
    }

    private func applyReactionRealtime(
        _ event: MessageRealtimeSignal.ReactionEvent,
        kind: MessageRealtimeSignal.Kind
    ) {
        guard messages.contains(where: { $0.id.rawValue == event.messageID }) else { return }
        let messageID = MessageID(event.messageID)
        let row = RoomMessageReaction(
            id: event.reactionID,
            messageID: RoomMessageID(event.messageID),
            userID: ProfileID(event.userID),
            reaction: event.emoji,
            createdAt: nil
        )
        switch kind {
        case .insert, .update:
            patchMessageReaction(messageID: messageID, row: row, mode: .insert)
        case .delete:
            patchMessageReaction(messageID: messageID, row: row, mode: .delete)
        }
    }

    private func patchMessageReaction(
        messageID: MessageID,
        row: RoomMessageReaction,
        mode: MessageReactionSemantics.PatchMode
    ) {
        messages = messages.map { message in
            guard message.id == messageID else { return message }
            var updated = message
            updated.roomReactions = MessageReactionSemantics.patch(
                message.roomReactions,
                next: row,
                mode: mode
            )
            return updated
        }
        syncThreadSessionCache(context: "reaction.patch")
    }

    private func logThreadStateDiagnostics(context: String) {
#if DEBUG
        let oldest = ConversationMessageMerge.sortByCreatedAt(messages).first?.id.rawValue
        ConversationThreadDiagnostics.logThreadState(
            messages: messages.count,
            oldestID: oldest,
            hasMore: hasMoreOlder,
            context: context
        )
        let rendered = buildTimeline(from: messages).filter {
            if case .message = $0 { return true }
            return false
        }.count
        ConversationThreadDiagnostics.logOpenPipeline(
            conversationID: conversationID.rawValue,
            stage: context,
            remoteReturned: nil,
            requestedPageSize: ConversationThreadSessionStore.messageLimit,
            cursor: nextOlderCursor,
            grdbOrDiskStored: nil,
            grdbOrDiskQueried: messages.count,
            viewModelAfter: messages.count,
            renderedCount: rendered,
            hasMoreOlder: hasMoreOlder,
            oldestMessageID: oldest,
            newestMessageID: ConversationMessageMerge.sortByCreatedAt(messages).last?.id.rawValue,
            initialScrollPhase: String(describing: initialScrollPhase)
        )
#endif
    }

    private var needsNewestWindowBackfill: Bool {
        ConversationThreadSessionStore.openThreadNeedsFullBootstrap(messageCount: messages.count)
    }

    /// Backfill the newest server window when deletes shrink the loaded page.
    private func revalidateNewestWindowIfNeededAfterDelete() async {
        guard needsNewestWindowBackfill,
              BackendV2FeatureFlags.isEnabled(.messageThreads),
              let viewerID,
              let rpc
        else { return }
        let generation = loadGeneration
        do {
            let result = try await ConversationThreadBootstrapLoader.load(
                viewerID: viewerID,
                conversationID: conversationID,
                cursor: nil,
                markRead: false,
                intent: .cacheRevalidation,
                rpc: rpc,
                detailCache: detailCache,
                inboxStore: inboxStore,
                loadGeneration: generation,
                currentGeneration: { self.loadGeneration },
                forceNetwork: true
            )
            guard generation == loadGeneration else { return }
            applyBootstrapMessages(result.applied.messages)
            nextOlderCursor = result.applied.nextCursor
            hasMoreOlder = result.applied.hasMoreMessages
            syncThreadSessionCache(context: "delete.backfill")
            hydrateSharedContent(from: result.applied.messages)
        } catch {
            // Soft-fail — synced local state remains authoritative for non-deleted rows.
        }
    }

    private func replaceMessages(_ incoming: [Message]) {
        messages = ConversationMessageMerge.mergeMessages(
            existing: [],
            incoming: incoming,
            viewerID: viewerID
        )
        notifyScrollContentApplied(source: .cacheApplied)
    }

    private func commitReconciledPage(_ incoming: [Message], recordScrollEvents: Bool = true) {
        let reconciled = ConversationMessageMerge.reconcileServerFirstPage(
            existing: messages,
            incoming: incoming
        )
        let filtered = filterSuppressed(reconciled)
        let previousIDs = Set(messages.map(\.id))
        let previousTempIDs = Set(
            messages
                .map(\.id)
                .filter(ConversationMessageMerge.isOptimisticMessageID)
        )
        messages = filtered
        let remainingIDs = Set(messages.map(\.id))
        for tempID in previousTempIDs where !remainingIDs.contains(tempID) {
            sendStates.removeValue(forKey: tempID)
        }
        syncThreadSessionCache(context: "reconcile-page")
        guard recordScrollEvents else { return }
        recordIncomingScrollEvents(incoming: incoming, previousIDs: previousIDs)
    }

    private func removeMessage(id: MessageID) {
        suppressedMessageIDs.insert(id)
        messages = ConversationMessageMerge.mergeMessages(
            existing: messages.filter { $0.id != id },
            incoming: [],
            viewerID: viewerID
        )
        sendStates.removeValue(forKey: id)
    }

    private func filterSuppressed(_ messages: [Message]) -> [Message] {
        guard !suppressedMessageIDs.isEmpty else { return messages }
        return messages.filter { !suppressedMessageIDs.contains($0.id) }
    }

    private func refreshInboxPreviewAfterDelete() {
        if let newest = MessageChronology.newest(in: messages) {
            patchInbox(with: newest, source: "deleteMessage")
            return
        }
        if var conversation {
            conversation.lastMessagePreview = nil
            conversation.lastMessageAt = nil
            conversation.lastMessageID = nil
            self.conversation = conversation
            inboxStore.upsertConversation(conversation)
        }
    }

    private func startOutboundSharedContentObserver() {
        stopOutboundSharedContentObserver()
        outboundSharedContentObserver = NotificationCenter.default.addObserver(
            forName: SharedContentOutboundDelivery.notification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let payload = note.object as? SharedContentOutboundDelivery.Payload else { return }
            Task { await self?.handleOutboundSharedContent(payload) }
        }
    }

    private func stopOutboundSharedContentObserver() {
        if let outboundSharedContentObserver {
            NotificationCenter.default.removeObserver(outboundSharedContentObserver)
            self.outboundSharedContentObserver = nil
        }
    }

    private func handleOutboundSharedContent(_ payload: SharedContentOutboundDelivery.Payload) async {
        guard case .dm(let id) = payload.destination, id == conversationID else { return }
        if let snapshot = payload.hydrationSnapshot {
            applySharedContentSnapshot(snapshot)
        }
        commitMessages([payload.message])
        hydrateSharedContent(from: [payload.message])
    }

    private func applySharedContentSnapshot(_ snapshot: SharedContentHydrator.Snapshot) {
        for (id, trade) in snapshot.sharedTrades { sharedTrades[id] = trade }
        for (id, post) in snapshot.sharedPosts { sharedPosts[id] = post }
        for (id, reel) in snapshot.sharedReels { sharedReels[id] = reel }
        for (id, achievement) in snapshot.sharedAchievements { sharedAchievements[id] = achievement }
        unavailableSharedContentKeys.formUnion(snapshot.unavailableSharedContentKeys)
    }

    /// Cache-first shared card hydration — never blocks the thread on network metadata.
    private func hydrateSharedContent(from messages: [Message]) {
        guard !messages.isEmpty else { return }
        primeSharedContentFromCaches(messages: messages)
        enqueueSharedContentNetworkHydration(messages: messages)
    }

    private func primeSharedContentFromCaches(messages: [Message]) {
        guard !messages.isEmpty else { return }
        let probe = SharedContentHydrationProbe.Session(surface: .dm)
        let context = sharedContentHydratorContext()
        SharedContentHydrator.primeFromCaches(
            messages: messages,
            sharedTrades: &sharedTrades,
            sharedPosts: &sharedPosts,
            sharedReels: &sharedReels,
            sharedAchievements: &sharedAchievements,
            unavailableSharedContentKeys: &unavailableSharedContentKeys,
            context: context,
            probe: probe
        )
    }

    private func enqueueSharedContentNetworkHydration(messages: [Message]) {
        sharedContentHydrationBacklog.append(contentsOf: messages)
        guard sharedContentHydrationTask == nil else { return }
        sharedContentHydrationTask = Task { @MainActor in
            defer { sharedContentHydrationTask = nil }
            while !sharedContentHydrationBacklog.isEmpty {
                let batch = sharedContentHydrationBacklog
                sharedContentHydrationBacklog = []
                await performSharedContentNetworkHydration(from: batch)
            }
        }
    }

    private func sharedContentHydratorContext() -> SharedContentHydrator.Context {
        SharedContentHydrator.Context(
            detailCache: detailCache,
            feedSessionStore: FeedSessionStore.shared,
            viewerID: viewerID,
            tradesRepo: tradesRepo,
            feedRepo: feedRepo,
            achievementsRepo: achievementsRepo,
            profilesRepo: profiles
        )
    }

    private func performSharedContentNetworkHydration(from messages: [Message]) async {
        guard !messages.isEmpty else { return }
        richContentHydrationCount += 1
        defer { richContentHydrationCount -= 1 }

        let probe = SharedContentHydrationProbe.Session(surface: .dm)
        let context = sharedContentHydratorContext()
        let hydrated = await SharedContentHydrator.hydrateMissing(
            messages: messages,
            snapshot: SharedContentHydrator.Snapshot(
                sharedTrades: sharedTrades,
                sharedPosts: sharedPosts,
                sharedReels: sharedReels,
                sharedAchievements: sharedAchievements,
                unavailableSharedContentKeys: unavailableSharedContentKeys
            ),
            context: context,
            probe: probe
        )
        sharedTrades = hydrated.sharedTrades
        sharedPosts = hydrated.sharedPosts
        sharedReels = hydrated.sharedReels
        sharedAchievements = hydrated.sharedAchievements
        unavailableSharedContentKeys = hydrated.unavailableSharedContentKeys
        persistSharedContentNetworkResults(hydrated, messages: messages, context: context)
    }

    private func persistSharedContentNetworkResults(
        _ snapshot: SharedContentHydrator.Snapshot,
        messages: [Message],
        context: SharedContentHydrator.Context
    ) {
        guard let viewerID = context.viewerID else { return }
        for (_, post) in snapshot.sharedPosts {
            SocialEntityPersistedCacheCoordinator.savePost(
                post,
                viewerID: viewerID,
                source: .share
            )
        }
        for (_, reel) in snapshot.sharedReels {
            SocialEntityPersistedCacheCoordinator.saveReel(
                reel,
                viewerID: viewerID,
                source: .share
            )
        }
        var persistedAchievementIDs = Set<AchievementID>()
        for message in messages {
            guard case .achievementPost(let postReference) = message.sharedContent else { continue }
            guard let achievement = SharedContentEntityPresentation.resolvedAchievement(
                forPostReference: postReference,
                detailCache: context.detailCache,
                sharedAchievements: snapshot.sharedAchievements
            ) else { continue }
            guard persistedAchievementIDs.insert(achievement.id).inserted else { continue }
            SocialEntityPersistedCacheCoordinator.saveAchievement(
                achievement,
                viewerID: viewerID,
                source: .share,
                messagePostReference: postReference
            )
        }
        for (_, trade) in snapshot.sharedTrades {
            if let summary = context.detailCache.tradeSummary(id: trade.id) {
                SocialEntityPersistedCacheCoordinator.saveTradeSummary(
                    summary,
                    viewerID: viewerID,
                    source: .share
                )
            }
        }
    }

    private func sendVoice(data: Data, duration: TimeInterval) async {
        guard let viewerID else { return }
        isSending = true
        defer { isSending = false }

        let tempID = MessageID("temp-\(UUID().uuidString)")
        let optimistic = Message(
            id: tempID,
            conversationID: conversationID,
            senderProfileID: viewerID,
            kind: .voice,
            body: nil,
            attachments: [
                MessageAttachment(
                    id: "local-voice",
                    media: MediaReference(id: "local-voice", kind: .audio, altText: nil),
                    tradeID: nil,
                    durationSeconds: duration
                ),
            ],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        commitMessages([optimistic])
        sendStates[tempID] = .sending
        scrollCoordinator.handle(
            .outgoingMessageInserted(messageID: tempID),
            conversationID: conversationID
        )

        if ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversationID)
        {
            sendStates[tempID] = .sent
            patchInbox(with: optimistic, source: "devVoiceSend")
            return
        }

        var uploadedAudioPath: String?
        do {
            let path = "\(viewerID.rawValue)/\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
            let reference = try await uploadService.upload(
                UploadRequest(
                    bucket: StorageBucket.messageAudio.rawValue,
                    path: path,
                    data: data,
                    contentType: "audio/mp4"
                )
            )
            uploadedAudioPath = reference.id
            let resolvedURL: String
            if let publicURL = objectStorage.publicURL(
                bucket: StorageBucket.messageAudio.rawValue,
                path: reference.id
            ) {
                resolvedURL = publicURL.absoluteString
            } else {
                resolvedURL = reference.id
            }

            var updated = optimistic
            updated.attachments = [
                MessageAttachment(
                    id: resolvedURL,
                    media: MediaReference(id: resolvedURL, kind: .audio, altText: nil),
                    tradeID: nil,
                    durationSeconds: duration
                ),
            ]
            commitMessages([updated], recordScrollEvents: false)

            let payload = Message(
                id: tempID,
                conversationID: conversationID,
                senderProfileID: viewerID,
                kind: .voice,
                body: nil,
                attachments: updated.attachments,
                replyToMessageID: nil,
                createdAt: .now,
                isReadByViewer: true
            )
            let saved = try await messagesRepo.send(payload)
            commitMessages([saved])
            sendStates.removeValue(forKey: tempID)
            sendStates[saved.id] = .sent
            patchInbox(with: saved, source: "confirmedVoiceSend")
            ExperienceHaptics.play(.messageSent)
        } catch {
            if let uploadedAudioPath {
                try? await objectStorage.delete(
                    bucket: StorageBucket.messageAudio.rawValue,
                    path: uploadedAudioPath
                )
            }
            sendStates[tempID] = .failed
            ExperienceHaptics.play(.error)
        }
    }

    private func rejectGuestMutationIfNeeded() -> Bool {
        guard ExploreModeSupport.isActive else { return false }
        DemoModeAuthGatePresenter.shared.requireAuthentication()
        return true
    }

    private func send(body: String, imageURL: String?, localImageData: Data?) async {
        guard !rejectGuestMutationIfNeeded() else { return }
        guard let viewerID, !isMessagingBlocked else { return }
        let blocksComposer = localImageData == nil
        if blocksComposer {
            isSending = true
        }
        defer {
            if blocksComposer { isSending = false }
        }

        let tempID = MessageID("temp-\(UUID().uuidString)")
        var attachments: [MessageAttachment] = []
        if let localImageData {
            attachments = OptimisticOutboundImageSendSupport.prepareOptimisticAttachments(
                tempID: tempID,
                localImageData: localImageData
            )
        } else if let imageURL {
            attachments = OptimisticOutboundImageSendSupport.imageAttachments(for: imageURL)
        }

        let optimistic = Message(
            id: tempID,
            conversationID: conversationID,
            senderProfileID: viewerID,
            kind: attachments.isEmpty ? .text : .media,
            body: body.isEmpty ? nil : body,
            attachments: attachments,
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        commitMessages([optimistic])
        sendStates[tempID] = .sending
        scrollCoordinator.handle(
            .outgoingMessageInserted(messageID: tempID),
            conversationID: conversationID
        )

        if ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversationID)
        {
            sendStates[tempID] = .sent
            patchInbox(with: optimistic, source: "devSend")
            return
        }

        await completeOptimisticSend(
            tempID: tempID,
            body: body,
            imageURL: imageURL,
            localImageData: localImageData
        )
    }

    private func resendFailedOptimisticImage(
        tempID: MessageID,
        body: String,
        localImageData: Data
    ) async {
        guard let viewerID, !isMessagingBlocked else { return }
        sendStates[tempID] = .sending
        if ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversationID)
        {
            sendStates[tempID] = .sent
            return
        }
        await completeOptimisticSend(
            tempID: tempID,
            body: body,
            imageURL: nil,
            localImageData: localImageData
        )
    }

    private func rollbackOptimisticSend(tempID: MessageID) {
        messages = messages.filter { $0.id != tempID }
        sendStates.removeValue(forKey: tempID)
        OptimisticOutboundImageStore.shared.remove(messageID: tempID)
        uploadedOutboundImageURLs.removeValue(forKey: tempID)
        syncThreadSessionCache(context: "proGateRollback")
    }

    private func completeOptimisticSend(
        tempID: MessageID,
        body: String,
        imageURL: String?,
        localImageData: Data?
    ) async {
        guard let viewerID else { return }
        do {
            var resolvedImageURL = imageURL
            if let localImageData {
                let path = StorageOptimizedMedia.objectPath(prefix: viewerID.rawValue, fileExtension: "jpg")
                resolvedImageURL = try await OptimisticOutboundImageSendSupport.uploadJPEG(
                    localImageData: localImageData,
                    storagePath: path,
                    uploadService: uploadService,
                    objectStorage: objectStorage
                )
                if let resolvedImageURL {
                    uploadedOutboundImageURLs[tempID] = resolvedImageURL
                }
            }

            let payload = Message(
                id: tempID,
                conversationID: conversationID,
                senderProfileID: viewerID,
                kind: resolvedImageURL == nil ? .text : .media,
                body: body.isEmpty ? "" : body,
                attachments: resolvedImageURL.map(OptimisticOutboundImageSendSupport.imageAttachments(for:)) ?? [],
                replyToMessageID: nil,
                createdAt: .now,
                isReadByViewer: true
            )
            AppLog.networking.info(
                """
                conversation.send invoking MessageRepository.send \
                convo=\(SafeInboxLog.hash(self.conversationID.rawValue), privacy: .public) \
                bodyChars=\(body.count, privacy: .public) \
                hasImage=\(resolvedImageURL != nil, privacy: .public)
                """
            )
            let saved = try await messagesRepo.send(payload)
            scrollCoordinator.handle(
                .optimisticConfirmed(from: tempID, to: saved.id),
                conversationID: conversationID
            )
            commitMessages([saved], recordScrollEvents: false)
            OptimisticOutboundImageStore.shared.remove(messageID: tempID)
            uploadedOutboundImageURLs.removeValue(forKey: tempID)
            sendStates.removeValue(forKey: tempID)
            sendStates[saved.id] = .sent
            patchInbox(with: saved, source: "confirmedSend")
            SafeInboxLog.sendCompleted(
                conversationID: saved.conversationID,
                messageID: saved.id,
                bodyChars: body.count,
                hasAttachment: resolvedImageURL != nil
            )
            ExperienceHaptics.play(.messageSent)
        } catch {
            AppLog.networking.error(
                """
                conversation.send failed \
                convo=\(SafeInboxLog.hash(self.conversationID.rawValue), privacy: .public) \
                bodyChars=\(body.count, privacy: .public) \
                error=\(String(describing: error), privacy: .public)
                """
            )
            if ProLimitPresentation.presentUpgradeIfProGate(error) {
                rollbackOptimisticSend(tempID: tempID)
            } else {
                sendStates[tempID] = .failed
                ExperienceHaptics.play(.error)
            }
        }
    }

    private func applyHeader(from conversation: Conversation?) {
        guard let conversation else { return }
        if conversation.isGroup {
            title = conversation.title ?? "Group Chat"
            subtitle = nil
        } else {
            title = conversation.title
                ?? peerProfile?.displayName
                ?? conversation.peerUsername
                ?? "Conversation"
            if let username = conversation.peerUsername ?? peerProfile?.username {
                subtitle = "@\(username)"
            }
        }
    }

    private func patchInbox(with message: Message, source: String = "unknown") {
        guard let viewerID else { return }
        inboxStore.patchFromMessage(
            message,
            viewerID: viewerID,
            conversationOpen: true,
            policy: .confirmedOutgoing,
            fallbackConversation: conversation,
            source: source
        )
        if let updated = inboxStore.conversations.first(where: { $0.id == conversationID }) {
            conversation = updated
        }
    }

    private func buildTimeline(from messages: [Message]) -> [ConversationTimelineItem] {
        var items: [ConversationTimelineItem] = []
        let calendar = Calendar.current
        var lastDay: DateComponents?
        let shareCaptions = SharedContentMessageSupport.bundleShareCaptions(in: messages)
        let visibleMessages = messages.filter { !shareCaptions.hiddenMessageIDs.contains($0.id) }
        for (index, message) in visibleMessages.enumerated() {
            let day = calendar.dateComponents([.year, .month, .day], from: message.createdAt)
            if day != lastDay {
                let key = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
                items.append(
                    .daySeparator(
                        id: key,
                        title: ConversationThreadSupport.daySeparator(message.createdAt)
                    )
                )
                lastDay = day
            }
            let previous = index > 0 ? visibleMessages[index - 1] : nil
            let next = index + 1 < visibleMessages.count ? visibleMessages[index + 1] : nil
            let isOutgoing = message.senderProfileID == viewerID
            let showsAvatar = !isOutgoing && (
                previous?.senderProfileID != message.senderProfileID
                    || previous.map { abs($0.createdAt.timeIntervalSince(message.createdAt)) > 300 } ?? true
            )
            let showsTimestamp = next?.senderProfileID != message.senderProfileID
                || next.map { abs($0.createdAt.timeIntervalSince(message.createdAt)) > 300 } ?? true
            items.append(
                .message(
                    ConversationBubbleItem(
                        id: message.id,
                        message: message,
                        isOutgoing: isOutgoing,
                        showsAvatar: showsAvatar,
                        showsTimestamp: showsTimestamp,
                        sendState: sendStates[message.id] ?? .sent,
                        shareUserCaption: shareCaptions.captionByShareID[message.id]
                    )
                )
            )
        }
        return items
    }
}
