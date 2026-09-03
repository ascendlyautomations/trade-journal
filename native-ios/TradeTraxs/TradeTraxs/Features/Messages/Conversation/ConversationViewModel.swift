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
    private(set) var tradePickerTrades: [Trade] = []
    private(set) var isLoadingTradePicker = false
    private(set) var sharedTrades: [TradeID: Trade] = [:]
    let scrollCoordinator = ConversationScrollCoordinator()

    enum InitialScrollPhase: Equatable {
        case pending
        case positioning
        case settling
        case confirmed
    }

    private(set) var initialScrollPhase: InitialScrollPhase = .pending
    private(set) var richContentHydrationCount = 0

    var isInitialScrollConfirmed: Bool { initialScrollPhase == .confirmed }

    /// True while the one-time open bottom pin is active (positioning or layout settling).
    var isInitialScrollPinningBottom: Bool {
        initialScrollPhase == .positioning || initialScrollPhase == .settling
    }

    /// Trade shares still awaiting hydration can resize the newest bubble after first layout.
    var hasPendingRichContentLayout: Bool {
        richContentHydrationCount > 0 || messages.contains(where: hasUnhydratedTradeShare)
    }

    private let messagesRepo: any MessageRepository
    private let profiles: any ProfileRepository
    private let notifications: (any NotificationRepository)?
    private let tradesRepo: (any TradeRepository)?
    private let session: any SessionProviding
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let realtimeHub: RealtimeHub?
    private let rpc: (any RPCClient)?

    private var nextOlderCursor: String?
    private var realtimeTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var isApplyingRealtime = false
    private var didMarkReadThisOpen = false
    private var loadGeneration: UInt64 = 0
    private var bootstrapMarkReadApplied = false
    /// Soft-deleted / locally removed rows — excluded from merge/realtime reconciliation.
    private var suppressedMessageIDs: Set<MessageID> = []

    init(
        conversationID: ConversationID,
        messages: any MessageRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        detailCache: DetailPresentationCache,
        trades: (any TradeRepository)? = nil,
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
    }

    var timeline: [ConversationTimelineItem] {
        buildTimeline(from: messages)
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
        guard loadTask == nil, phase != .loaded else { return }
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
                await hydrateSharedTrades(from: result.applied.messages)
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
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            // Register topic + join web-equivalent messages postgres_changes. Remain idle — no polling.
            let channel = RealtimeChannelID(
                kind: .conversation,
                topic: conversationID.rawValue
            )
            try? await realtimeHub?.subscriptions.subscribe(channel)
            let token = await session.accessToken
            guard let realtimeHub else { return }
            for await signal in realtimeHub.watchConversationMessages(
                conversationID: conversationID,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                await applyRealtimeSignal(signal)
            }
        }
    }

    func stopRealtime() {
        syncThreadSessionCache(context: "leave")
        VoiceMessagePlaybackController.shared.stopAll()
        realtimeTask?.cancel()
        realtimeTask = nil
        if inboxStore.activeConversationID == conversationID {
            inboxStore.setActiveConversation(nil)
        }
        Task { [conversationID, realtimeHub] in
            let channel = RealtimeChannelID(
                kind: .conversation,
                topic: conversationID.rawValue
            )
            try? await realtimeHub?.subscriptions.unsubscribe(channel)
            await realtimeHub?.stopWatchingConversationMessages(conversationID: conversationID)
        }
    }

    func sendText() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        await send(body: text, imageURL: nil, localImageData: nil)
    }

    func sendImage(_ image: UIImage) async {
        guard !isSending else { return }
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        await send(body: draft.trimmingCharacters(in: .whitespacesAndNewlines), imageURL: nil, localImageData: data)
        draft = ""
    }

    func sendVoice(localFileURL: URL, duration: TimeInterval) async {
        guard !isSending else { return }
        defer { try? FileManager.default.removeItem(at: localFileURL) }
        guard let data = try? Data(contentsOf: localFileURL) else { return }
        await sendVoice(data: data, duration: duration)
    }

    func presentTradePicker() {
        ExperienceHaptics.play(.selection)
        showsTradePicker = true
    }

    func loadTradePickerIfNeeded() async {
        guard tradePickerTrades.isEmpty, !isLoadingTradePicker else { return }
        guard let viewerID, let tradesRepo else { return }
        isLoadingTradePicker = true
        defer { isLoadingTradePicker = false }
        if ConversationThreadSupport.isLocalDevelopment(viewerID) {
            tradePickerTrades = TradeShareFixtures.sampleTrades(ownerID: viewerID)
            return
        }
        do {
            let page = try await tradesRepo.trades(
                ownedBy: viewerID,
                accountID: nil,
                page: PageRequest(limit: 40),
                publicOnly: false
            )
            tradePickerTrades = page.items
        } catch {
            tradePickerTrades = []
        }
    }

    func sendTrade(_ trade: Trade) async {
        guard let viewerID, !isSending else { return }
        showsTradePicker = false
        sharedTrades[trade.id] = trade
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
                    id: trade.id.rawValue,
                    media: MediaReference(id: trade.id.rawValue, kind: .file, altText: "Shared trade"),
                    tradeID: trade.id
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
            sharedTrades[trade.id] = trade
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
        guard let tradeID = message.attachments.first?.tradeID else { return nil }
        return sharedTrades[tradeID]
    }

    func retry(_ item: ConversationBubbleItem) async {
        guard sendStates[item.id] == .failed else { return }
        removeMessage(id: item.id)
        sendStates.removeValue(forKey: item.id)
        let imageURL = item.imageReference?.id
        await send(body: item.text ?? "", imageURL: imageURL, localImageData: nil)
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
        phase = .loading
        // Web optimistic clear on open — badge drops before history finishes loading.
        inboxStore.markRead(conversationID: conversationID)
        inboxStore.setActiveConversation(conversationID)

        let current = await session.currentUserID
        let viewer = current.map { ProfileID($0.rawValue) }
        viewerID = viewer

        do {
            if let viewer,
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
            phase = .loaded
            startRealtime()
        } catch ConversationThreadBootstrapLoader.LoaderError.rpcUnavailable {
            do {
                try await loadFromRepository()
                await markConversationSeenIfNeeded()
                phase = .loaded
                startRealtime()
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
              !ConversationThreadSupport.isLocalDevelopment(viewerID),
              !ConversationThreadSupport.isLocalConversation(conversationID)
        else { return }

        if BackendV2FeatureFlags.isEnabled(.messageThreads), bootstrapMarkReadApplied {
            return
        }

        await markMessageNotificationsRead()
        inboxStore.markRead(conversationID: conversationID)
    }

    /// Web `messages/[id]` marks all unread `type=message` Activity rows on open.
    private func markMessageNotificationsRead() async {
        guard let notifications else { return }
        guard let page = try? await notifications.notifications(page: PageRequest(limit: 100)) else {
            return
        }
        for item in page.items where !item.isRead && item.kind == .message {
            try? await notifications.markRead(id: item.id)
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
        await hydrateSharedTrades(from: messages)
    }

    private func loadFromV2Bootstrap(
        viewerID: ProfileID,
        generation: UInt64,
        unreadBeforeOpen: Int,
        forceNetwork: Bool
    ) async throws {
        guard let rpc else { throw ConversationThreadBootstrapLoader.LoaderError.flagOff }

        let cacheKey = ConversationThreadSessionStore.cacheKey(
            viewerID: viewerID,
            conversationID: conversationID
        )
        let cached = ConversationThreadSessionStore.shared.restore(key: cacheKey)

        if let cached, !forceNetwork {
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
            startRealtime()
            let needsWindowBackfill = cached.messages.count < ConversationThreadSessionStore.messageLimit
                && cached.hasMoreMessages
            if !cached.isSoftStale, unreadBeforeOpen == 0, !needsWindowBackfill {
                logThreadStateDiagnostics(context: "cache.reopen.skip-network")
                return
            }
        }

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

        if result.cacheHit {
            applyBootstrapApplied(result.applied)
            await hydrateSharedTrades(from: result.applied.messages)
            return
        }

        applyBootstrapApplied(result.applied)
        bootstrapMarkReadApplied = result.applied.markReadApplied
        await hydrateSharedTrades(from: result.applied.messages)
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
            if let peerID = peerProfileID {
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
    }

    /// Web `mergeMessageLists(wire, existing)` — bootstrap must not wipe newer local rows.
    private func applyBootstrapMessages(_ incoming: [Message]) {
        let reconciled = ConversationMessageMerge.reconcileServerFirstPage(
            existing: messages,
            incoming: incoming
        )
        messages = filterSuppressed(reconciled)
    }

    /// Pull-to-refresh / explicit refresh — not used on a timer.
    private func fetchIncrementalUpdates() async {
        await applyRealtimeSignal(MessageRealtimeSignal(kind: .insert, messageID: nil))
    }

    /// Incremental apply from Realtime — never reloads the whole conversation on V2.
    private func applyRealtimeSignal(_ signal: MessageRealtimeSignal) async {
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
            await hydrateSharedTrades(from: page.items)
            if let newest = ConversationMessageMerge.sortByCreatedAt(messages).last {
                patchInbox(with: newest, source: "legacyRealtime")
            }
        } catch {
            // Soft-fail event-driven hydrate.
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
            if messages.contains(where: { $0.id == messageID }) {
                if let newest = ConversationMessageMerge.sortByCreatedAt(messages).last {
                    patchInbox(with: newest, source: "realtimeDedupe")
                }
                return
            }
        }

        guard signal.kind == .insert || signal.kind == .update else { return }

        // Incoming from another device — merge first page only when thread is open.
        isApplyingRealtime = true
        defer { isApplyingRealtime = false }
        guard let rpc else { return }
        let generation = loadGeneration
        do {
            let result = try await ConversationThreadBootstrapLoader.load(
                viewerID: viewerID!,
                conversationID: conversationID,
                cursor: nil,
                markRead: false,
                intent: .cacheRevalidation,
                rpc: rpc,
                detailCache: detailCache,
                inboxStore: inboxStore,
                loadGeneration: generation,
                currentGeneration: { self.loadGeneration },
                forceNetwork: false
            )
            guard generation == self.loadGeneration else { return }
            applyBootstrapApplied(result.applied)
            await hydrateSharedTrades(from: result.applied.messages)
            if let newest = ConversationMessageMerge.sortByCreatedAt(messages).last {
                inboxStore.patchFromMessage(
                    newest,
                    viewerID: viewerID!,
                    conversationOpen: true,
                    policy: .canonical,
                    fallbackConversation: conversation,
                    source: "realtimeV2"
                )
            }
        } catch {
            // Soft-fail — local confirmed-send patch remains authoritative.
        }
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

    private func logThreadStateDiagnostics(context: String) {
#if DEBUG
        let oldest = ConversationMessageMerge.sortByCreatedAt(messages).first?.id.rawValue
        ConversationThreadDiagnostics.logThreadState(
            messages: messages.count,
            oldestID: oldest,
            hasMore: hasMoreOlder,
            context: context
        )
#endif
    }

    private var needsNewestWindowBackfill: Bool {
        messages.count < ConversationThreadSessionStore.messageLimit && hasMoreOlder
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
            await hydrateSharedTrades(from: result.applied.messages)
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

    private func hydrateSharedTrades(from messages: [Message]) async {
        guard let tradesRepo else { return }
        let ids = Array(
            Set(
                messages.compactMap { message -> TradeID? in
                    guard let id = message.attachments.first?.tradeID else { return nil }
                    return sharedTrades[id] == nil ? id : nil
                }
            )
        )
        guard !ids.isEmpty else { return }
        richContentHydrationCount += 1
        defer { richContentHydrationCount -= 1 }
        let fetched = (try? await SessionTradeEntityStore.shared.trades(
            ids: ids,
            detailCache: detailCache,
            repository: tradesRepo
        )) ?? []
        for trade in fetched {
            sharedTrades[trade.id] = trade
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
            sendStates[tempID] = .failed
            ExperienceHaptics.play(.error)
        }
    }

    private func send(body: String, imageURL: String?, localImageData: Data?) async {
        guard let viewerID, !isMessagingBlocked else { return }
        isSending = true
        defer { isSending = false }

        let tempID = MessageID("temp-\(UUID().uuidString)")
        var attachments: [MessageAttachment] = []
        if let imageURL {
            attachments = [
                MessageAttachment(
                    id: imageURL,
                    media: MediaReference(id: imageURL, kind: .image, altText: nil),
                    tradeID: nil
                ),
            ]
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

        do {
            var resolvedImageURL = imageURL
            if let localImageData {
                let path = "\(viewerID.rawValue)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
                let reference = try await uploadService.upload(
                    UploadRequest(
                        bucket: StorageBucket.screenshots.rawValue,
                        path: path,
                        data: localImageData,
                        contentType: "image/jpeg",
                        purpose: .tradeScreenshot
                    )
                )
                if let publicURL = objectStorage.publicURL(
                    bucket: StorageBucket.screenshots.rawValue,
                    path: reference.id
                ) {
                    resolvedImageURL = publicURL.absoluteString
                } else {
                    resolvedImageURL = reference.id
                }
                if let url = resolvedImageURL {
                    var updated = optimistic
                    updated.attachments = [
                        MessageAttachment(
                            id: url,
                            media: MediaReference(id: url, kind: .image, altText: nil),
                            tradeID: nil
                        ),
                    ]
                    updated.kind = .media
                    commitMessages([updated], recordScrollEvents: false)
                }
            }

            let payload = Message(
                id: tempID,
                conversationID: conversationID,
                senderProfileID: viewerID,
                kind: resolvedImageURL == nil ? .text : .media,
                body: body.isEmpty ? "" : body,
                attachments: resolvedImageURL.map {
                    [
                        MessageAttachment(
                            id: $0,
                            media: MediaReference(id: $0, kind: .image, altText: nil),
                            tradeID: nil
                        ),
                    ]
                } ?? [],
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
            sendStates[tempID] = .failed
            ExperienceHaptics.play(.error)
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
        for (index, message) in messages.enumerated() {
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
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
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
                        sendState: sendStates[message.id] ?? .sent
                    )
                )
            )
        }
        return items
    }

    private func hasUnhydratedTradeShare(_ message: Message) -> Bool {
        guard let tradeID = message.attachments.first?.tradeID else { return false }
        return sharedTrades[tradeID] == nil
    }
}
