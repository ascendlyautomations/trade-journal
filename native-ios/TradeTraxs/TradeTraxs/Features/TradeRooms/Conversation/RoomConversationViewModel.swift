import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class RoomConversationViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let roomID: RoomID

    private(set) var phase: Phase = .idle
    private(set) var room: TradeRoom?
    private(set) var membership: RoomMembership?
    private(set) var joinRequestState: TradeRoomJoinRequestState?
    private(set) var ownerProfile: Profile?
    private(set) var channels: [RoomChannel] = []
    private(set) var selectedChannelID: RoomChannelID?
    private(set) var messages: [Message] = []
    private(set) var senderProfiles: [ProfileID: Profile] = [:]
    /// Bumps when ``senderProfiles`` changes so timeline rows re-resolve identity.
    private(set) var senderProfileGeneration = 0
    private(set) var sendStates: [MessageID: ConversationBubbleItem.SendState] = [:]
    private(set) var isLoadingOlder = false
    private(set) var hasMoreOlder = true
    private(set) var isJoining = false
    private(set) var viewerID: ProfileID?
    /// Restored scroll anchor when switching back to a previously loaded channel.
    private(set) var pendingScrollMessageID: MessageID?
    /// Deep-link highlight (Trade Room push / Activity mention).
    private(set) var highlightedMessageID: MessageID?
    var draft = ""
    var isSending = false
    var showsTradePicker = false
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
    private(set) var activePresenceMembers: [RoomActivePresenceMember] = []
    var showsActivePresenceSheet = false
    var pendingDeleteMessage: ConversationBubbleItem?
    var showsDeleteMessageConfirmation = false
    var deleteErrorMessage: String?
    var showsLeaveRoomConfirmation = false

    /// Prefer resolved UUID after slug deep-link lookup.
    private var resolvedRoomID: RoomID { room?.id ?? roomID }
    private var pendingDeepLinkFocus: RoomNavigationFocusStore.Focus?

    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let notifications: (any NotificationRepository)?
    private let tradesRepo: (any TradeRepository)?
    private let feedRepo: (any FeedRepository)?
    private let achievementsRepo: (any AchievementRepository)?
    private let rpc: (any RPCClient)?
    private let session: any SessionProviding
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let realtimeHub: RealtimeHub?
    private let navigationCoordinator: NavigationCoordinator?
    private let navigationHost: TradeRoomNavigationHost

    private var nextOlderCursor: String?
    private var realtimeTask: Task<Void, Never>?
    private var roomLiveRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var isRoomLiveRealtimeActive = false
    private var loadTask: Task<Void, Never>?
    private var channelLoadTasks: [RoomChannelID: Task<Void, Never>] = [:]
    private var channelCaches: [RoomChannelID: ChannelThreadCache] = [:]
    private var channelMetadataCached = false
    private var isApplyingRealtime = false
    private var didMarkReadThisOpen = false
    private var reactionBusyKeys: Set<String> = []
    private var retryingMessageIDs: Set<MessageID> = []
    private var deletingMessageIDs: Set<MessageID> = []
    private var outboundSharedContentObserver: NSObjectProtocol?
    private var sharedContentHydrationTask: Task<Void, Never>?
    private var sharedContentHydrationBacklog: [Message] = []
    private let messagesRepo: (any MessageRepository)?
    @ObservationIgnored private nonisolated(unsafe) var blockObserver: NSObjectProtocol?

    init(
        roomID: RoomID,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        detailCache: DetailPresentationCache,
        trades: (any TradeRepository)? = nil,
        feed: (any FeedRepository)? = nil,
        achievements: (any AchievementRepository)? = nil,
        notifications: (any NotificationRepository)? = nil,
        rpc: (any RPCClient)? = nil,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages,
        realtimeHub: RealtimeHub? = nil,
        inboxStore: MessagesInboxStore? = nil,
        messages: (any MessageRepository)? = nil
    ) {
        self.roomID = roomID
        self.rooms = rooms
        self.profiles = profiles
        self.notifications = notifications
        self.tradesRepo = trades
        self.feedRepo = feed
        self.achievementsRepo = achievements
        self.rpc = rpc
        self.session = session
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.realtimeHub = realtimeHub
        self.inboxStore = inboxStore ?? .shared
        self.messagesRepo = messages
        self.pendingDeepLinkFocus = RoomNavigationFocusStore.shared.consume(for: roomID)
        blockObserver = NotificationCenter.default.addObserver(
            forName: .userBlockListDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.applyBlockedAuthorsToRoomThreads()
            }
        }
    }

    deinit {
        if let blockObserver {
            NotificationCenter.default.removeObserver(blockObserver)
        }
    }

    func clearHighlightedMessage() {
        highlightedMessageID = nil
    }

    var selectedChannel: RoomChannel? {
        channels.first { $0.id == selectedChannelID }
    }

    var conversationID: ConversationID {
        ConversationID(selectedChannelID?.rawValue ?? roomID.rawValue)
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

    var newestMessageID: MessageID? {
        messages.last?.id
    }

    var showsEmpty: Bool {
        phase == .loaded
            && selectedChannelID != nil
            && timeline.filter({
                if case .message = $0 { return true }
                return false
            }).isEmpty
    }

    /// Keep header / composer when the thread already has content (offline refresh failures).
    var showsRoomChrome: Bool {
        phase == .loaded || (room != nil && !messages.isEmpty)
    }

    var title: String {
        room?.name ?? "Trade Room"
    }

    var memberCountLabel: String {
        let count = inboxStore.rooms.first(where: { $0.id == resolvedRoomID })?.memberCount
            ?? room?.memberCount
        guard let count else { return "" }
        return "\(ProfileDisplay.compactCount(count)) members"
    }

    var isMember: Bool {
        if membership != nil { return true }
        return inboxStore.rooms.contains { $0.id == resolvedRoomID }
    }

    /// Approval-policy rooms hide member-only content until membership is granted.
    var canViewMessages: Bool {
        if isOwner || isMember { return true }
        guard let room else { return false }
        if room.joinPolicy == .approval { return false }
        if joinRequestState == .pending { return false }
        return true
    }

    var showsJoinPreviewPlaceholder: Bool {
        guard phase == .loaded, let room else { return false }
        return !canViewMessages && room.joinPolicy == .approval
    }

    var joinPreviewMessage: String {
        if joinRequestState == .pending || joinPresentationState == .requested {
            return "Your request is pending. You'll see messages after the owner approves."
        }
        return "Request to join this room to read and send messages."
    }

    var isOwner: Bool {
        guard let viewerID, let room else { return false }
        return room.ownerProfileID == viewerID
    }

    var canManageRoom: Bool {
        guard let room else { return false }
        return TradeRoomManagementPermission.canManage(room: room, viewerID: viewerID)
    }

    private var tagStore: SessionRoomMemberTagsStore { .shared }

    /// Member/owner shell — composer may still be read-only on announcement channels.
    var canShowComposer: Bool {
        guard selectedChannel != nil else { return false }
        return isOwner || isMember
    }

    /// Composer stays visible for empty threads and while channel metadata is resolving — independent of header chrome.
    var shouldShowMessageComposer: Bool {
        guard canViewMessages, !showsJoinPreviewPlaceholder else { return false }
        guard canShowComposer else { return false }
        if phase == .loaded || showsEmpty || !messages.isEmpty { return true }
        return room != nil && selectedChannel != nil
    }

    /// Web `canPostInRoom` — owner bypasses channel chat lock.
    var canPostInSelectedChannel: Bool {
        guard selectedChannel != nil else { return false }
        if isOwner { return true }
        return selectedChannel?.allowMembersChat ?? true
    }

    var canCompose: Bool {
        canShowComposer && canPostInSelectedChannel
    }

    var canReact: Bool {
        canShowComposer && viewerID != nil
    }

    var showsActivePresence: Bool {
        false
    }

    func openActivePresence() {
        ExperienceHaptics.play(.selection)
        showsActivePresenceSheet = true
    }

    func closeActivePresence() {
        showsActivePresenceSheet = false
    }

    func reactionSummaries(for message: Message) -> [RoomMessageReactionSummary] {
        RoomMessageReactionSemantics.aggregate(message.roomReactions, viewerID: viewerID)
    }

    func reactionConfiguration(for message: Message) -> MessageReactionConfiguration? {
        guard canReact || !message.roomReactions.isEmpty else { return nil }
        let summaries = reactionSummaries(for: message).map(MessageReactionSummary.init)
        return MessageReactionConfiguration(
            summaries: summaries,
            supportedEmojis: RoomMessageReactionSemantics.supportedEmojis,
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
        let skipNetwork = MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || roomID.rawValue.hasPrefix("dev-")
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
                return try await self.rooms.insertMessageReaction(
                    roomID: self.resolvedRoomID,
                    messageID: RoomMessageID(optimistic.messageID.rawValue),
                    userID: optimistic.userID,
                    reaction: optimistic.reaction
                )
            },
            delete: { [weak self] reactionID in
                try await self?.rooms.deleteMessageReaction(id: reactionID)
            }
        )
    }

    var joinButtonTitle: String {
        if isOwner { return "Owner" }
        guard let room else { return "Join" }
        return TradeRoomJoinPresentation.previewButtonTitle(
            joinPolicy: room.joinPolicy,
            state: joinPresentationState
        )
    }

    var joinPresentationState: TradeRoomDiscoveryJoinState {
        if isOwner || isMember { return .joined }
        if isJoining {
            return room?.joinPolicy == .approval ? .requesting : .joining
        }
        if joinRequestState == .pending { return .requested }
        if let roomID = room?.id,
           TradeRoomJoinActionCoordinator.shared.mutationStates[roomID] == .requested
        {
            return .requested
        }
        return .idle
    }

    var isJoinButtonEnabled: Bool {
        !isOwner && TradeRoomJoinPresentation.isInteractive(joinPresentationState) && !isJoining
    }

    var showsJoinButton: Bool {
        TradeRoomJoinPresentation.showsButton(
            isOwner: isOwner,
            state: joinPresentationState
        )
    }

    var isMuted: Bool {
        inboxStore.isRoomMuted(roomID)
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded, phase != .loading else { return }
        loadTask = Task { await performInitialLoad() }
    }

    func retryLoad() {
        guard loadTask == nil else { return }
        phase = .idle
        channelCaches = [:]
        channelMetadataCached = false
        loadTask = Task { await performInitialLoad() }
    }

    /// Applies room metadata edits from Manage Room / Room Information without reloading messages.
    func reloadRoomMetadataIfNeeded() async {
        guard phase == .loaded else { return }
        do {
            let loaded = try await rooms.room(id: resolvedRoomID)
            room = loaded
            await reconcileMemberCount(source: .mutation)
        } catch {
            // Soft-fail — stale header is acceptable until next full load.
        }
    }

    /// Refreshes channel list after owner CRUD; preserves selection when possible.
    func reloadChannelsIfNeeded() async {
        guard phase == .loaded else { return }
        do {
            let previousSelected = selectedChannelID
            let loaded = try await rooms.channels(roomID: resolvedRoomID)
                .sorted { $0.position < $1.position }
            let removedIDs = Set(channels.map(\.id)).subtracting(loaded.map(\.id))
            for channelID in removedIDs {
                channelCaches.removeValue(forKey: channelID)
                channelLoadTasks[channelID]?.cancel()
                channelLoadTasks.removeValue(forKey: channelID)
            }
            channels = loaded
            if let previousSelected,
               loaded.contains(where: { $0.id == previousSelected })
            {
                selectedChannelID = previousSelected
            } else if let first = loaded.first {
                selectedChannelID = first.id
                if channelCaches[first.id]?.isLoaded != true {
                    replaceMessages([])
                    nextOlderCursor = nil
                    hasMoreOlder = true
                    pendingScrollMessageID = nil
                    loadChannelMessagesIfNeeded(first.id)
                }
            } else {
                selectedChannelID = nil
                replaceMessages([])
            }
        } catch {
            // Soft-fail — channel switcher may be stale until next full load.
        }
    }

    /// Switch channel without recreating the room shell — swaps message list + cache only.
    func selectChannel(_ channelID: RoomChannelID) {
        guard channelID != selectedChannelID else { return }
        ExperienceHaptics.play(.selection)
        persistActiveChannelCache(scrollAnchor: messages.last?.id)
        selectedChannelID = channelID
        if let cached = channelCaches[channelID], cached.isLoaded {
            apply(cache: cached)
            pendingScrollMessageID = cached.scrollAnchorMessageID
        } else {
            replaceMessages([])
            nextOlderCursor = nil
            hasMoreOlder = true
            pendingScrollMessageID = nil
            loadChannelMessagesIfNeeded(channelID)
        }
    }

    func loadOlderIfNeeded() async {
        guard hasMoreOlder, !isLoadingOlder, phase == .loaded else { return }
        guard let channel = selectedChannel else {
            hasMoreOlder = false
            return
        }
        guard let viewerID, !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) else {
            hasMoreOlder = false
            return
        }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            var page = PageRequest(limit: 40)
            page.cursor = nextOlderCursor
            let result = try await rooms.messages(roomID: roomID, channel: channel, page: page)
            let mapped = result.items.map(RoomMessageMapping.displayMessage)
            commitMessages(mapped)
            await hydrateSenders(for: mapped)
            nextOlderCursor = result.nextCursor
            hasMoreOlder = result.nextCursor != nil
            persistActiveChannelCache(scrollAnchor: nil)
            await hydrateSharedContent(from: mapped)
        } catch {
            // Soft-fail older page.
        }
    }

    func startRealtime() {
        guard !ExploreModeSupport.isActive else { return }
        guard realtimeHub != nil else { return }
        if isRoomLiveRealtimeActive,
           roomLiveRealtimeConsumer != nil,
           realtimeTask != nil,
           roomLiveRealtimeConsumer?.routeKey == "room:\(resolvedRoomID.rawValue)"
        {
            RoomRealtimeLog.subscribed(roomID: resolvedRoomID, reason: "already-active")
            inboxStore.setActiveRoom(resolvedRoomID)
            return
        }
        inboxStore.setActiveRoom(resolvedRoomID)
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            if let previous = roomLiveRealtimeConsumer {
                RoomRealtimeLog.unsubscribed(roomID: self.resolvedRoomID, reason: "replace-before-resubscribe")
                await realtimeHub?.releaseWatch(previous)
                roomLiveRealtimeConsumer = nil
            }
            let activeRoomID = self.resolvedRoomID
            let channel = RealtimeChannelID(kind: .room, topic: activeRoomID.rawValue)
            try? await realtimeHub?.subscriptions.subscribe(channel)
            let token = await session.accessToken
            guard let realtimeHub else { return }

            let streams = realtimeHub.watchRoomLive(
                roomID: activeRoomID,
                accessToken: token,
                presenceTrack: nil,
                debugOwner: "RoomConversation"
            )
            roomLiveRealtimeConsumer = streams.consumer
            isRoomLiveRealtimeActive = true
            RoomRealtimeLog.subscribed(roomID: activeRoomID, reason: "room-joined")
            SocialRealtimeRepairSurfaces.shared.repairOpenRoom = { [weak self] in
                await self?.repairMissedRoomMessagesAfterReconnect()
            }

            for await signal in streams.messages {
                guard !Task.isCancelled else { break }
                await applyRealtimeSignal(signal)
            }
            isRoomLiveRealtimeActive = false
        }
    }

    func stopRealtime() {
        RoomRealtimeLog.unsubscribed(roomID: resolvedRoomID, reason: "room-disappear")
        VoiceMessagePlaybackController.shared.stopAll()
        activePresenceMembers = []
        stopOutboundSharedContentObserver()
        if inboxStore.activeRoomID == resolvedRoomID {
            inboxStore.setActiveRoom(nil)
        }
        SocialRealtimeRepairSurfaces.shared.repairOpenRoom = nil
        realtimeTask?.cancel()
        realtimeTask = nil
        isRoomLiveRealtimeActive = false
        let consumer = roomLiveRealtimeConsumer
        roomLiveRealtimeConsumer = nil
        Task { [roomID, realtimeHub, consumer] in
            let channel = RealtimeChannelID(kind: .room, topic: roomID.rawValue)
            try? await realtimeHub?.subscriptions.unsubscribe(channel)
            await realtimeHub?.releaseWatch(consumer)
        }
        persistActiveChannelCache(scrollAnchor: messages.last?.id)
    }

    func sendText() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, canPostInSelectedChannel else { return }
        draft = ""
        await send(body: text, imageURL: nil, localImageData: nil)
    }

    func sendImage(_ image: UIImage) async {
        guard canPostInSelectedChannel else { return }
        guard let data = MediaImagePreparation.chatJPEGData(from: image) else { return }
        await send(
            body: draft.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: nil,
            localImageData: data
        )
        draft = ""
    }

    func sendVoice(localFileURL: URL, duration: TimeInterval) async {
        guard !isSending, canPostInSelectedChannel else { return }
        defer { try? FileManager.default.removeItem(at: localFileURL) }
        guard let data = try? Data(contentsOf: localFileURL) else { return }
        await sendVoice(data: data, duration: duration)
    }

    func presentTradePicker() {
        ExperienceHaptics.play(.selection)
        showsTradePicker = true
    }

    func loadTradePickerIfNeeded() async {
        guard tradePickerSummaries.isEmpty, !isLoadingTradePicker else { return }
        guard let viewerID else { return }
        isLoadingTradePicker = true
        defer { isLoadingTradePicker = false }
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            tradePickerSummaries = TradeShareFixtures.sampleTrades(ownerID: viewerID).map {
                TradeSummaryMapper.summary(fromPartialListTrade: $0)
            }
            return
        }
        guard let tradesRepo else { return }
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
        let summary =
            tradePickerSummaries.first(where: { $0.id == trade.id })
            ?? TradeSummaryMapper.summary(fromPartialListTrade: trade)
        await sendTradeSummary(summary)
    }

    func sendTradeSummary(_ summary: TradeSummary) async {
        guard let viewerID, !isSending, canPostInSelectedChannel, let channelID = selectedChannelID else { return }
        showsTradePicker = false
        sharedTrades[summary.id] = TradeSummaryMapper.previewTrade(from: summary)
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

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            sendStates[tempID] = .sent
            persistActiveChannelCache(scrollAnchor: tempID)
            patchInboxPreview(with: optimistic)
            return
        }

        do {
            let payload = RoomMessage(
                id: RoomMessageID(tempID.rawValue),
                roomID: roomID,
                senderProfileID: viewerID,
                body: "Shared a trade",
                attachedTradeID: summary.id,
                media: [],
                parentMessageID: nil,
                channelID: channelID,
                isPinned: false,
                createdAt: .now
            )
            let savedRoom = try await rooms.send(payload)
            let saved = RoomMessageMapping.displayMessage(from: savedRoom)
            commitMessages([saved])
            sendStates.removeValue(forKey: tempID)
            sendStates[saved.id] = .sent
            sharedTrades[summary.id] = TradeSummaryMapper.previewTrade(from: summary)
            persistActiveChannelCache(scrollAnchor: saved.id)
            patchInboxPreview(with: saved)
            ExperienceHaptics.play(.messageSent)
        } catch {
            await handleSendFailure(
                tempID: tempID,
                optimistic: optimistic,
                channelID: channelID,
                content: "Shared a trade",
                error: error
            )
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
        guard case .achievementPost(let id) = message.sharedContent else { return nil }
        return sharedAchievements[AchievementID(id.rawValue)]
    }

    func isSharedContentUnavailable(_ message: Message) -> Bool {
        guard let reference = message.sharedContent else { return false }
        return unavailableSharedContentKeys.contains(reference.stableKey)
    }

    func senderProfile(for profileID: ProfileID) -> Profile? {
        if let profile = senderProfiles[profileID] {
            return profile
        }
        return detailCache.profile(id: profileID)
    }

    func authorProfile(for profileID: ProfileID) -> Profile? {
        senderProfile(for: profileID)
    }

    func canDeleteMessage(_ item: ConversationBubbleItem) -> Bool {
        guard item.isOutgoing else { return false }
        guard item.message.kind != .system else { return false }
        if item.sendState == .failed { return true }
        guard item.sendState == .sent else { return false }
        guard !ConversationMessageMerge.isOptimisticMessageID(item.message.id) else { return false }
        guard !deletingMessageIDs.contains(item.id) else { return false }
        return true
    }

    func requestDeleteMessage(_ item: ConversationBubbleItem) {
        guard canDeleteMessage(item) else { return }
        ExperienceHaptics.play(.warning)
        pendingDeleteMessage = item
        showsDeleteMessageConfirmation = true
    }

    func cancelDeleteMessage() {
        pendingDeleteMessage = nil
        showsDeleteMessageConfirmation = false
    }

    func confirmDeleteMessage() async {
        showsDeleteMessageConfirmation = false
        guard let item = pendingDeleteMessage else { return }
        pendingDeleteMessage = nil
        await deleteMessage(item)
    }

    private func deleteMessage(_ item: ConversationBubbleItem) async {
        guard canDeleteMessage(item) else { return }
        deleteErrorMessage = nil

        if item.sendState == .failed {
            removeMessage(id: item.id)
            persistActiveChannelCache(scrollAnchor: messages.last?.id)
            refreshInboxPreviewAfterDelete()
            return
        }

        if let viewerID,
           MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || roomID.rawValue.hasPrefix("dev-")
        {
            removeMessage(id: item.id)
            persistActiveChannelCache(scrollAnchor: messages.last?.id)
            refreshInboxPreviewAfterDelete()
            return
        }

        let snapshot = item.message
        deletingMessageIDs.insert(item.id)
        removeMessage(id: item.id)
        persistActiveChannelCache(scrollAnchor: messages.last?.id)

        defer { deletingMessageIDs.remove(item.id) }

        do {
            try await rooms.deleteMessage(
                roomID: resolvedRoomID,
                messageID: RoomMessageID(snapshot.id.rawValue)
            )
            ExperienceHaptics.play(.success)
            refreshInboxPreviewAfterDelete()
        } catch {
            commitMessages([snapshot])
            persistActiveChannelCache(scrollAnchor: messages.last?.id)
            deleteErrorMessage = ConversationThreadSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    func retry(_ item: ConversationBubbleItem) async {
        guard sendStates[item.id] == .failed else { return }
        guard !retryingMessageIDs.contains(item.id) else { return }
        retryingMessageIDs.insert(item.id)
        defer { retryingMessageIDs.remove(item.id) }

        if ConversationMessageMerge.isOptimisticMessageID(item.id),
           let localData = OptimisticOutboundImageStore.shared.jpegData(for: item.id),
           let channelID = selectedChannelID
        {
            await resendFailedOptimisticImage(
                tempID: item.id,
                body: item.text ?? "",
                localImageData: localData,
                channelID: channelID,
                optimisticCreatedAt: item.message.createdAt
            )
            return
        }

        if let channelID = selectedChannelID,
           let reconciled = await reconcileOptimisticSend(
               tempID: item.id,
               sentAt: item.message.createdAt,
               content: item.text ?? item.message.body,
               channelID: channelID
           )
        {
            commitMessages([reconciled])
            OptimisticOutboundImageStore.shared.remove(messageID: item.id)
            sendStates.removeValue(forKey: item.id)
            sendStates[reconciled.id] = .sent
            persistActiveChannelCache(scrollAnchor: reconciled.id)
            patchInboxPreview(with: reconciled)
            return
        }

        removeMessage(id: item.id)
        sendStates.removeValue(forKey: item.id)
        let imageURL = item.imageReference?.id
        guard let imageURL, !OptimisticOutboundImageSupport.isOptimisticMediaID(imageURL) else { return }
        await send(body: item.text ?? "", imageURL: imageURL, localImageData: nil)
    }

    func toggleMute() {
        ExperienceHaptics.play(.selection)
        inboxStore.toggleMute(roomID: roomID)
    }

    func requestLeaveRoom() {
        guard isMember, !isOwner else { return }
        ExperienceHaptics.play(.warning)
        showsLeaveRoomConfirmation = true
    }

    func cancelLeaveRoom() {
        showsLeaveRoomConfirmation = false
    }

    func confirmLeaveRoom() async {
        showsLeaveRoomConfirmation = false
        guard let viewerID, isMember, !isOwner else { return }
        if ExploreModeSupport.isActive {
            DemoModeAuthGatePresenter.shared.requireAuthentication()
            return
        }
        isJoining = true
        defer { isJoining = false }
        ExperienceHaptics.play(.warning)
        let targetID = resolvedRoomID
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || targetID.rawValue.hasPrefix("dev-") {
            membership = nil
            joinRequestState = nil
            inboxStore.removeRoom(id: targetID)
            ExperienceHaptics.play(.success)
            navigationCoordinator?.pop()
            return
        }
        do {
            try await rooms.leave(roomID: targetID, profileID: viewerID)
            membership = nil
            joinRequestState = nil
            inboxStore.removeRoom(id: targetID)
            SessionMemberRoomsStore.shared.invalidate(viewerID: viewerID)
            TradeRoomJoinActionCoordinator.shared.clearMutation(for: targetID)
            await reconcileMemberCount(source: .mutation)
            ExperienceHaptics.play(.success)
            navigationCoordinator?.pop()
        } catch {
            ExperienceHaptics.play(.error)
        }
    }

    func toggleMembership() async {
        guard let viewerID, !isOwner, !isJoining else { return }
        if ExploreModeSupport.isActive {
            DemoModeAuthGatePresenter.shared.requireAuthentication()
            return
        }
        isJoining = true
        defer { isJoining = false }
        ExperienceHaptics.play(.selection)
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            if membership == nil {
                membership = RoomMembership(
                    roomID: roomID,
                    profileID: viewerID,
                    role: .member,
                    joinedAt: .now,
                    notificationsEnabled: true
                )
            } else {
                membership = nil
            }
            ExperienceHaptics.play(.success)
            return
        }
        do {
            if membership == nil {
                if room?.joinPolicy == .approval {
                    let priorRequestState = joinRequestState
                    joinRequestState = .pending
                    TradeRoomJoinActionCoordinator.shared.patchRequested(resolvedRoomID)
                    do {
                        let status = try await rooms.requestJoin(roomID: roomID)
                        joinRequestState = status == .approved ? nil : .pending
                        if status == .approved {
                            membership = try? await rooms.membership(roomID: roomID, profileID: viewerID)
                            TradeRoomJoinActionCoordinator.shared.patchJoined(resolvedRoomID)
                            GettingStartedRefreshCenter.noteJoinedOtherTradeRoom(
                                viewer: viewerID,
                                roomOwnerProfileID: room?.ownerProfileID,
                                isViewerRoomOwner: isOwner
                            )
                            await reconcileMemberCount(source: .mutation)
                            try? await reloadMessagesAfterMembershipGranted()
                        }
                        ExperienceHaptics.play(.success)
                        return
                    } catch {
                        joinRequestState = priorRequestState
                        if isAlreadyPendingJoinError(error) {
                            joinRequestState = .pending
                            TradeRoomJoinActionCoordinator.shared.patchRequested(resolvedRoomID)
                            ExperienceHaptics.play(.success)
                            return
                        }
                        TradeRoomJoinActionCoordinator.shared.clearMutation(for: resolvedRoomID)
                        ExperienceHaptics.play(.error)
                        return
                    }
                }
                membership = try await rooms.join(roomID: roomID, profileID: viewerID)
                GettingStartedRefreshCenter.noteJoinedOtherTradeRoom(
                    viewer: viewerID,
                    roomOwnerProfileID: room?.ownerProfileID,
                    isViewerRoomOwner: isOwner
                )
                TradeRoomJoinActionCoordinator.shared.patchJoined(resolvedRoomID)
                await reconcileMemberCount(source: .mutation)
            } else {
                try await rooms.leave(roomID: roomID, profileID: viewerID)
                membership = nil
                joinRequestState = nil
                await reconcileMemberCount(source: .mutation)
            }
            ExperienceHaptics.play(.success)
        } catch {
            if room?.joinPolicy == .approval,
               let status = try? await rooms.viewerJoinRequest(roomID: roomID),
               status == .pending
            {
                joinRequestState = .pending
                TradeRoomJoinActionCoordinator.shared.patchRequested(resolvedRoomID)
            } else {
                ExperienceHaptics.play(.error)
            }
        }
    }

    func openMembers() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.members(roomID))
    }

    func openRoomInfo() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.info(roomID))
    }

    func openManageRoom() {
        guard canManageRoom else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.manageRoom(roomID))
    }

    func openRoomSettings() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.roomSettings(roomID))
    }

    func openProfile(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.profile(profileID))
    }

    func clearPendingScroll() {
        pendingScrollMessageID = nil
    }

    // MARK: - Private

    private struct ChannelThreadCache {
        var messages: [Message]
        var nextOlderCursor: String?
        var hasMoreOlder: Bool
        var scrollAnchorMessageID: MessageID?
        var isLoaded: Bool
    }

    private func performInitialLoad() async {
        phase = .loading
        // Web optimistic clear when the room is selected — badge drops before history finishes.
        inboxStore.markRoomRead(roomID: roomID)
        inboxStore.setActiveRoom(roomID)

        let current = await session.currentUserID
        let viewer = current.map { ProfileID($0.rawValue) }
        viewerID = viewer

        if let messagesRepo, viewer != nil, shouldApplyBlockedAuthorFilter {
            await FeedBlockedAuthorsFilter.shared.syncFromServer(messages: messagesRepo, force: false)
        }

        var hydratedFromDisk = false
        if let viewer,
           !MessagesInboxSupport.isLocalDevelopmentProfile(viewer),
           !roomID.rawValue.hasPrefix("dev-"),
           let disk = SocialPersistedCacheCoordinator.restoreRoomSnapshot(viewerID: viewer, roomID: roomID)
        {
            applyDiskSnapshot(disk)
            hydratedFromDisk = true
            phase = .loaded
        }

        do {
            if let viewer, DemoExploreTradeRoom.isLocalRoom(roomID) {
                await loadDemoExploreTradeRoomFixtures(viewerID: viewer)
            } else if let viewer,
                      DemoExperienceSupport.usesLocalBundledSocialData(viewer)
                      || roomID.rawValue.hasPrefix("dev-")
            {
                await loadLocalFixtures(viewerID: viewer)
            } else if ExploreModeSupport.isActive, let viewer, let rpc {
                let bootstrapped = await loadFromPublicGuestBootstrap(rpc: rpc, viewerID: viewer)
                if !bootstrapped, !hydratedFromDisk {
                    try await loadFromRepository()
                }
            } else if let viewer, let rpc {
                let bootstrapped = await loadFromRoomBootstrap(rpc: rpc, viewerID: viewer)
                if bootstrapped {
                    // RPC bootstrap applied — skip fragmented REST shell load.
                } else if hydratedFromDisk, membership == nil {
                    SocialPersistedCacheCoordinator.invalidateRoomSnapshot(viewerID: viewer, roomID: roomID)
                    channelCaches = [:]
                    replaceMessages([])
                    hasMoreOlder = false
                    try await loadFromRepository()
                } else if !hydratedFromDisk {
                    try await loadFromRepository()
                }
            } else if !hydratedFromDisk {
                try await loadFromRepository()
            }
            // Web waits until messages finished loading, then `mark_room_read`.
            await markRoomSeenIfNeeded(force: false)
            await reconcileMemberCount(source: .network)
            phase = .loaded
            if !messages.isEmpty {
                await hydrateSenders(for: messages)
                await hydrateSharedContent(from: messages)
            }
            startRealtime()
            startOutboundSharedContentObserver()
        } catch {
            await markRoomSeenIfNeeded(force: false)
            phase = .failed(ConversationThreadSupport.message(for: error))
        }
        loadTask = nil
    }

    /// Web `markAllRoomMessagesSeenForUser` + room Activity notification clear.
    private func markRoomSeenIfNeeded(force: Bool) async {
        inboxStore.markRoomRead(roomID: roomID)
        if didMarkReadThisOpen, !force { return }
        didMarkReadThisOpen = true

        guard let viewerID,
              !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID),
              !roomID.rawValue.hasPrefix("dev-")
        else { return }

        try? await rooms.markRead(roomID: roomID)
        await markRoomNotificationsRead()
        inboxStore.markRoomRead(roomID: roomID)
    }

    /// Web `markNotificationsReadForTarget({ kind: "room" })`.
    private func markRoomNotificationsRead() async {
        guard let notifications else { return }
        let started = CFAbsoluteTimeGetCurrent()
        let slug = room?.slug
        let markedLocally = ActivityInboxStore.shared.markRoomNotificationsReadLocally(
            roomID: roomID,
            slug: slug
        )
        do {
            _ = try await notifications.markRoomNotificationsRead(roomID: roomID, slug: slug)
            NotificationReadDiagnostics.logBulkMarkRead(
                ids: markedLocally,
                requests: 1,
                dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            )
        } catch {
            // Activity reconciles on next bootstrap.
        }
    }

    private func loadDemoExploreTradeRoomFixtures(viewerID: ProfileID) async {
        let fixtureRoom = DemoExploreTradeRoom.room()
        room = fixtureRoom
        membership = nil
        joinRequestState = nil
        ownerProfile = DemoExploreTradeRoom.hostProfile()
        detailCache.seed(DemoExploreTradeRoom.hostProfile())
        mergeSenderProfiles(DemoExploreTradeRoom.memberProfiles(viewerID: viewerID), source: "demoExploreRoom")

        channels = DemoExploreTradeRoom.channels(roomID: roomID)
        channelMetadataCached = true
        applyPendingDeepLinkFocusSelectingChannel()
        if selectedChannelID == nil {
            selectedChannelID = channels.first?.id
        }

        for channel in channels {
            let roomMessages = DemoExploreTradeRoom.messages(
                roomID: roomID,
                viewerID: viewerID,
                channelID: channel.id
            )
            let mapped = roomMessages.map(RoomMessageMapping.displayMessage)
            channelCaches[channel.id] = ChannelThreadCache(
                messages: mapped.sorted { $0.createdAt < $1.createdAt },
                nextOlderCursor: nil,
                hasMoreOlder: false,
                scrollAnchorMessageID: mapped.last?.id,
                isLoaded: true
            )
        }

        if let selectedChannelID, let cache = channelCaches[selectedChannelID] {
            apply(cache: cache)
            await hydrateSenders(for: cache.messages)
        }
        applyPendingDeepLinkFocusHighlight()
        phase = .loaded
        if let tradeID = DemoCanonicalDataset.trades().first?.id,
           let trade = try? await tradesRepo?.trade(id: tradeID)
        {
            sharedTrades[trade.id] = trade
        }
    }

    private func loadLocalFixtures(viewerID: ProfileID) async {
        let fixtureRoom = TradeRoomsFixtures.room(id: roomID, ownerID: viewerID)
            ?? inboxStore.rooms.first { $0.id == roomID }
            ?? TradeRoom(
                id: roomID,
                ownerProfileID: viewerID,
                name: "Trade Room",
                slug: roomID.rawValue,
                description: "Community discussion.",
                image: nil,
                memberCount: 12,
                showsOnProfile: true,
                createdAt: .now
            )
        room = fixtureRoom
        membership = RoomMembership(
            roomID: roomID,
            profileID: viewerID,
            role: fixtureRoom.ownerProfileID == viewerID ? .owner : .member,
            joinedAt: fixtureRoom.createdAt,
            notificationsEnabled: !inboxStore.isRoomMuted(roomID)
        )
        let owner = FollowListFixtures.profile(id: fixtureRoom.ownerProfileID)
            ?? Profile(
                id: fixtureRoom.ownerProfileID,
                userID: UserID(fixtureRoom.ownerProfileID.rawValue),
                username: "owner",
                displayName: "Room Owner",
                bio: nil,
                avatar: nil,
                traderType: .futures,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: true,
                createdAt: fixtureRoom.createdAt
            )
        ownerProfile = owner
        detailCache.seed(owner)
        mergeSenderProfiles([owner], source: "fixtureOwner")

        channels = TradeRoomsFixtures.channels(roomID: roomID)
        channelMetadataCached = true
        applyPendingDeepLinkFocusSelectingChannel()
        if selectedChannelID == nil {
            selectedChannelID = channels.first?.id
        }

        for channel in channels {
            let roomMessages = TradeRoomsFixtures.messages(
                roomID: roomID,
                viewerID: viewerID,
                channelID: channel.id
            )
            let mapped = roomMessages.map(RoomMessageMapping.displayMessage)
            channelCaches[channel.id] = ChannelThreadCache(
                messages: mapped.sorted { $0.createdAt < $1.createdAt },
                nextOlderCursor: nil,
                hasMoreOlder: false,
                scrollAnchorMessageID: mapped.last?.id,
                isLoaded: true
            )
        }

        if let selectedChannelID, let cache = channelCaches[selectedChannelID] {
            apply(cache: cache)
            await hydrateSenders(for: cache.messages)
        }
        applyPendingDeepLinkFocusHighlight()
        for trade in TradeShareFixtures.sampleTrades(ownerID: viewerID) {
            sharedTrades[trade.id] = trade
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitesting-trade-rooms-channel-trades"),
           let trades = channels.first(where: { $0.name.lowercased() == "trades" })
        {
            selectChannel(trades.id)
        }
        #endif
    }

    private func loadFromPublicGuestBootstrap(rpc: any RPCClient, viewerID: ProfileID) async -> Bool {
        do {
            let applied = try await PublicRoomGuestBootstrapLoader.load(
                roomID: roomID,
                viewerID: viewerID,
                rpc: rpc,
                detailCache: detailCache
            )
            room = applied.room
            membership = nil
            channels = applied.channels
            channelMetadataCached = true
            selectedChannelID = applied.selectedChannelID
            applyPendingDeepLinkFocusSelectingChannel()
            let cache = ChannelThreadCache(
                messages: applied.channelCache.messages,
                nextOlderCursor: applied.channelCache.nextOlderCursor,
                hasMoreOlder: applied.channelCache.hasMoreOlder,
                scrollAnchorMessageID: applied.channelCache.scrollAnchorMessageID,
                isLoaded: applied.channelCache.isLoaded
            )
            channelCaches[applied.selectedChannelID] = cache
            apply(cache: cache)
            await hydrateSenders(for: cache.messages)
            await hydrateSharedContent(from: cache.messages)
            applyPendingDeepLinkFocusHighlight()
            if let last = cache.messages.last {
                patchInboxPreview(with: last)
            }
            persistRoomSnapshotToDisk()
            return true
        } catch PublicRoomGuestBootstrapLoader.LoaderError.flagOff,
                PublicRoomGuestBootstrapLoader.LoaderError.rpcUnavailable,
                PublicRoomGuestBootstrapLoader.LoaderError.roomNotPublic {
            return false
        } catch {
            return false
        }
    }

    private func loadFromRoomBootstrap(rpc: any RPCClient, viewerID: ProfileID) async -> Bool {
        do {
            let applied = try await RoomBootstrapLoader.load(
                roomID: roomID,
                viewerID: viewerID,
                rpc: rpc,
                detailCache: detailCache
            )
            room = applied.room
            membership = applied.membership
            if let cached = detailCache.profile(id: applied.room.ownerProfileID) {
                ownerProfile = cached
                mergeSenderProfiles([cached], source: "ownerCache")
            } else if let owner = try? await SessionProfileStore.shared.profiles(
                ids: [applied.room.ownerProfileID],
                detailCache: detailCache,
                repository: profiles
            ).first {
                ownerProfile = owner
                mergeSenderProfiles([owner], source: "ownerBatch")
            }
            channels = applied.channels
            channelMetadataCached = true
            selectedChannelID = applied.selectedChannelID
            applyPendingDeepLinkFocusSelectingChannel()
            let cache = ChannelThreadCache(
                messages: applied.channelCache.messages,
                nextOlderCursor: applied.channelCache.nextOlderCursor,
                hasMoreOlder: applied.channelCache.hasMoreOlder,
                scrollAnchorMessageID: applied.channelCache.scrollAnchorMessageID,
                isLoaded: applied.channelCache.isLoaded
            )
            channelCaches[applied.selectedChannelID] = cache
            if canViewMessages {
                apply(cache: cache)
                await hydrateSenders(for: cache.messages)
                await hydrateSharedContent(from: cache.messages)
                applyPendingDeepLinkFocusHighlight()
                if let last = cache.messages.last {
                    patchInboxPreview(with: last)
                }
            } else {
                replaceMessages([])
                hasMoreOlder = false
                if membership == nil, applied.room.joinPolicy == .approval {
                    joinRequestState = try? await rooms.viewerJoinRequest(roomID: applied.room.id)
                }
            }
            if applied.markReadApplied {
                didMarkReadThisOpen = true
            }
            RoomMemberCountProbe.record(
                roomID: applied.room.id,
                displayedMemberCount: applied.room.memberCount,
                activeMembershipCount: applied.room.memberCount,
                loadedMemberListCount: nil,
                source: .bootstrap
            )
            await reconcileMemberCount(source: .bootstrap)
            persistRoomSnapshotToDisk()
            return true
        } catch RoomBootstrapLoader.LoaderError.flagOff,
                RoomBootstrapLoader.LoaderError.rpcUnavailable {
            return false
        } catch {
            return false
        }
    }

    private func loadFromRepository() async throws {
        if !channelMetadataCached || room == nil {
            let loaded = try await rooms.room(id: roomID)
            room = loaded
            let activeRoomID = loaded.id
            if let viewerID {
                membership = try? await rooms.membership(roomID: activeRoomID, profileID: viewerID)
                if membership == nil, loaded.joinPolicy == .approval {
                    joinRequestState = try? await rooms.viewerJoinRequest(roomID: activeRoomID)
                } else {
                    joinRequestState = nil
                }
            }
            if let cached = detailCache.profile(id: loaded.ownerProfileID) {
                ownerProfile = cached
                mergeSenderProfiles([cached], source: "ownerCache")
            } else if let owner = try? await SessionProfileStore.shared.profiles(
                ids: [loaded.ownerProfileID],
                detailCache: detailCache,
                repository: profiles
            ).first {
                ownerProfile = owner
                mergeSenderProfiles([owner], source: "ownerBatch")
            }
            channels = try await rooms.channels(roomID: activeRoomID)
            channelMetadataCached = true
            if isMember || isOwner,
               let management = rooms as? any RoomManagementRepository
            {
                try? await tagStore.hydrate(roomID: activeRoomID, repository: management)
            }
            applyPendingDeepLinkFocusSelectingChannel()
            if selectedChannelID == nil || !channels.contains(where: { $0.id == selectedChannelID }) {
                selectedChannelID = channels.first?.id
            }
        }

        guard let channelID = selectedChannelID else {
            replaceMessages([])
            hasMoreOlder = false
            return
        }
        guard canViewMessages else {
            replaceMessages([])
            hasMoreOlder = false
            return
        }
        try await fetchChannelMessages(channelID)
        applyPendingDeepLinkFocusHighlight()
    }

    private func reconcileMemberCount(source: RoomMemberCountProbe.Source) async {
        let id = resolvedRoomID
        let count: Int
        if let authoritative = try? await rooms.activeMemberCounts(for: [id])[id] {
            count = authoritative
        } else if let fallback = room?.memberCount {
            count = fallback
        } else {
            return
        }
        if var updated = room {
            updated.memberCount = count
            room = updated
        }
        RoomMemberCountSync.apply(
            roomID: id,
            count: count,
            inboxStore: inboxStore,
            viewerID: viewerID
        )
        RoomMemberCountProbe.record(
            roomID: id,
            displayedMemberCount: count,
            activeMembershipCount: count,
            loadedMemberListCount: nil,
            source: source
        )
    }

    /// Selects the deep-linked channel before the first message fetch.
    private func applyPendingDeepLinkFocusSelectingChannel() {
        guard let focus = pendingDeepLinkFocus else { return }
        if let channelID = focus.channelID {
            if channels.contains(where: { $0.id == channelID }) {
                selectedChannelID = channelID
                return
            }
            let needle = channelID.rawValue.lowercased()
            if let match = channels.first(where: {
                $0.id.rawValue.lowercased() == needle
                    || $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle
                    || $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "#\(needle)"
            }) {
                selectedChannelID = match.id
            }
        }
    }

    /// Scrolls / highlights the deep-linked message after the channel thread loads.
    private func applyPendingDeepLinkFocusHighlight() {
        guard let focus = pendingDeepLinkFocus else { return }
        pendingDeepLinkFocus = nil
        if let messageID = focus.messageID {
            pendingScrollMessageID = messageID
            highlightedMessageID = messageID
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                if highlightedMessageID == messageID {
                    highlightedMessageID = nil
                }
            }
        }
    }

    private func loadChannelMessagesIfNeeded(_ channelID: RoomChannelID) {
        guard canViewMessages else { return }
        if channelCaches[channelID]?.isLoaded == true { return }
        if channelLoadTasks[channelID] != nil { return }
        channelLoadTasks[channelID] = Task { [weak self] in
            guard let self else { return }
            defer { self.channelLoadTasks[channelID] = nil }
            if let viewerID,
               MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
                || roomID.rawValue.hasPrefix("dev-")
            {
                let roomMessages = TradeRoomsFixtures.messages(
                    roomID: roomID,
                    viewerID: viewerID,
                    channelID: channelID
                )
                let mapped = roomMessages.map(RoomMessageMapping.displayMessage)
                let sorted = ConversationMessageMerge.mergeMessages(
                    existing: [],
                    incoming: mapped,
                    viewerID: viewerID
                )
                let cache = ChannelThreadCache(
                    messages: sorted,
                    nextOlderCursor: nil,
                    hasMoreOlder: false,
                    scrollAnchorMessageID: sorted.last?.id,
                    isLoaded: true
                )
                channelCaches[channelID] = cache
                if selectedChannelID == channelID {
                    apply(cache: cache)
                }
                await hydrateSenders(for: sorted)
                return
            }
            do {
                try await fetchChannelMessages(channelID)
            } catch {
                // Soft-fail channel load; room shell stays up.
            }
        }
    }

    private func fetchChannelMessages(_ channelID: RoomChannelID) async throws {
        let channel = channels.first { $0.id == channelID }
        let page = try await rooms.messages(
            roomID: roomID,
            channel: channel,
            page: PageRequest(limit: 50)
        )
        let mapped = page.items.map(RoomMessageMapping.displayMessage)
        let sorted = ConversationMessageMerge.mergeMessages(
            existing: [],
            incoming: mapped,
            viewerID: viewerID
        )
        let cache = ChannelThreadCache(
            messages: sorted,
            nextOlderCursor: page.nextCursor,
            hasMoreOlder: page.nextCursor != nil,
            scrollAnchorMessageID: sorted.last?.id,
            isLoaded: true
        )
        channelCaches[channelID] = cache
        if selectedChannelID == channelID {
            apply(cache: cache)
        }
        await hydrateSenders(for: sorted)
        await hydrateSharedContent(from: sorted)
        if let last = sorted.last, channelID == selectedChannelID {
            patchInboxPreview(with: last)
        }
    }

    private func apply(cache: ChannelThreadCache) {
        replaceMessages(cache.messages)
        nextOlderCursor = cache.nextOlderCursor
        hasMoreOlder = cache.hasMoreOlder
    }

    private func persistActiveChannelCache(scrollAnchor: MessageID?) {
        guard let selectedChannelID else { return }
        var existing = channelCaches[selectedChannelID] ?? ChannelThreadCache(
            messages: [],
            nextOlderCursor: nil,
            hasMoreOlder: true,
            scrollAnchorMessageID: nil,
            isLoaded: false
        )
        existing.messages = messages
        existing.nextOlderCursor = nextOlderCursor
        existing.hasMoreOlder = hasMoreOlder
        if let scrollAnchor {
            existing.scrollAnchorMessageID = scrollAnchor
        }
        existing.isLoaded = true
        channelCaches[selectedChannelID] = existing
        persistRoomSnapshotToDisk()
    }

    private func applyDiskSnapshot(_ disk: SocialDiskCache.RoomSnapshotBlob) {
        room = disk.room
        membership = disk.membership
        channels = disk.channels
        channelMetadataCached = true
        if let rawSelected = disk.selectedChannelID {
            let selected = RoomChannelID(rawSelected)
            selectedChannelID = selected
        } else {
            selectedChannelID = channels.first?.id
        }
        var restoredCaches: [RoomChannelID: ChannelThreadCache] = [:]
        for (key, thread) in disk.channelThreads {
            let channelID = RoomChannelID(key)
            restoredCaches[channelID] = ChannelThreadCache(
                messages: thread.messages,
                nextOlderCursor: thread.nextOlderCursor,
                hasMoreOlder: thread.hasMoreOlder,
                scrollAnchorMessageID: thread.messages.last?.id,
                isLoaded: thread.isLoaded
            )
        }
        channelCaches = restoredCaches
        if let selectedChannelID, let cache = channelCaches[selectedChannelID] {
            apply(cache: cache)
        }
    }

    private func persistRoomSnapshotToDisk() {
        guard let viewerID, let room else { return }
        let channelThreads = Dictionary(uniqueKeysWithValues: channelCaches.map { entry in
            (
                entry.key,
                SocialDiskCache.RoomChannelThreadBlob(
                    channelID: entry.key.rawValue,
                    messages: entry.value.messages,
                    nextOlderCursor: entry.value.nextOlderCursor,
                    hasMoreOlder: entry.value.hasMoreOlder,
                    isLoaded: entry.value.isLoaded
                )
            )
        })
        SocialPersistedCacheCoordinator.persistRoomSnapshot(
            viewerID: viewerID,
            roomID: roomID,
            room: room,
            membership: membership,
            channels: channels,
            selectedChannelID: selectedChannelID,
            channelThreads: channelThreads
        )
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
        guard case .room(let deliveredRoomID, let channelID) = payload.destination,
              deliveredRoomID == roomID
        else { return }
        if let channelID, selectedChannelID != channelID { return }
        commitMessages([payload.message])
        await hydrateSharedContent(from: [payload.message])
        persistActiveChannelCache(scrollAnchor: messages.last?.id)
    }

    private func hydrateSharedContent(from messages: [Message]) async {
        guard !messages.isEmpty else { return }
        sharedContentHydrationBacklog.append(contentsOf: messages)
        if let existing = sharedContentHydrationTask {
            await existing.value
            return
        }
        sharedContentHydrationTask = Task { @MainActor in
            defer { sharedContentHydrationTask = nil }
            while !sharedContentHydrationBacklog.isEmpty {
                let batch = sharedContentHydrationBacklog
                sharedContentHydrationBacklog = []
                await performSharedContentHydration(from: batch)
            }
        }
        await sharedContentHydrationTask?.value
    }

    private func performSharedContentHydration(from messages: [Message]) async {
        guard !messages.isEmpty else { return }

        let probe = SharedContentHydrationProbe.Session(surface: .tradeRoom)
        let context = SharedContentHydrator.Context(
            detailCache: detailCache,
            feedSessionStore: FeedSessionStore.shared,
            viewerID: viewerID,
            tradesRepo: tradesRepo,
            feedRepo: feedRepo,
            achievementsRepo: achievementsRepo,
            profilesRepo: profiles
        )

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
    }

    fileprivate func repairMissedRoomMessagesAfterReconnect() async {
        guard let viewerID, let channel = selectedChannel else { return }
        guard !isApplyingRealtime else { return }
        isApplyingRealtime = true
        defer { isApplyingRealtime = false }
        do {
            let page = try await rooms.messages(
                roomID: roomID,
                channel: channel,
                page: PageRequest(limit: 30)
            )
            let mapped = page.items.map(RoomMessageMapping.displayMessage)
            commitMessages(mapped)
            persistActiveChannelCache(scrollAnchor: messages.last?.id)
            if let last = messages.last {
                patchInboxPreview(with: last)
            }
            await hydrateSenders(for: mapped)
            _ = viewerID
        } catch {
            // Non-destructive — keep cached thread.
        }
    }

    /// Incremental apply from Realtime — never reloads the whole room.
    private func applyRealtimeSignal(_ signal: MessageRealtimeSignal) async {
        if let reaction = signal.reactionEvent {
            applyReactionRealtime(reaction, kind: signal.kind)
            return
        }

        guard let viewerID,
              !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID),
              !roomID.rawValue.hasPrefix("dev-"),
              let channel = selectedChannel,
              !isApplyingRealtime
        else { return }

        if signal.kind == .delete, let rawID = signal.messageID {
            removeMessage(id: MessageID(rawID))
            persistActiveChannelCache(scrollAnchor: messages.last?.id)
            return
        }

        if signal.kind == .insert, let rawID = signal.messageID {
            if messages.contains(where: { $0.id == MessageID(rawID) }) {
#if DEBUG
                MessagingRealtimeDebugLog.messageEchoIgnored(messageID: rawID, source: "room-thread")
#endif
                return
            }
            if !MessagingRealtimeDeliveryCoordinator.claimMessageInsert(
                domain: "room-thread",
                messageID: rawID,
                conversationID: roomID.rawValue
            ) {
                return
            }
        }

        isApplyingRealtime = true
        defer { isApplyingRealtime = false }

        var merged: Message?
        if let payload = signal.recordPayload {
            merged = MessageRealtimeMerge.roomDisplayMessage(from: payload)
        }
        if merged == nil, let rawID = signal.messageID {
#if DEBUG
            MessagingRealtimeDebugLog.networkFallback(reason: "room_single_page_fallback")
#endif
            do {
                let page = try await rooms.messages(
                    roomID: roomID,
                    channel: channel,
                    page: PageRequest(limit: 1)
                )
                merged = page.items.first.map(RoomMessageMapping.displayMessage)
                _ = rawID
            } catch {
                return
            }
        }
        guard let incoming = merged else { return }

        let beforeIDs = Set(messages.map(\.id))
        commitMessages([incoming])
        let addedPeerMessage = incoming.senderProfileID != viewerID && !beforeIDs.contains(incoming.id)
        await hydrateSenders(for: [incoming])
        persistActiveChannelCache(scrollAnchor: messages.last?.id)
        await hydrateSharedContent(from: [incoming])
        patchInboxPreview(with: incoming)
#if DEBUG
        MessagingRealtimeDebugLog.roomInsert(
            roomID: roomID.rawValue,
            messageID: incoming.id.rawValue,
            source: "roomThread"
        )
#endif
        if addedPeerMessage {
            await markRoomSeenIfNeeded(force: true)
        }
    }

    /// Sole write path for thread rows — web `mergeMessages` semantics.
    private func commitMessages(_ incoming: [Message]) {
        let previousTempIDs = Set(
            messages
                .map(\.id)
                .filter(ConversationMessageMerge.isOptimisticMessageID)
        )
        let filteredIncoming = filterMessagesForBlockedAuthors(incoming)
        messages = ConversationMessageMerge.mergeMessages(
            existing: messages,
            incoming: filteredIncoming,
            viewerID: viewerID
        )
        let remainingIDs = Set(messages.map(\.id))
        for tempID in previousTempIDs where !remainingIDs.contains(tempID) {
            sendStates.removeValue(forKey: tempID)
        }
    }

    private func replaceMessages(_ incoming: [Message]) {
        messages = ConversationMessageMerge.mergeMessages(
            existing: [],
            incoming: filterMessagesForBlockedAuthors(incoming),
            viewerID: viewerID
        )
    }

    private var shouldApplyBlockedAuthorFilter: Bool {
        !ExploreModeSupport.skipsAuthenticatedViewerServices
    }

    private func filterMessagesForBlockedAuthors(_ incoming: [Message]) -> [Message] {
        guard shouldApplyBlockedAuthorFilter else { return incoming }
        return FeedBlockedAuthorsFilter.shared.filterConversationMessages(incoming, viewerID: viewerID)
    }

    private func applyBlockedAuthorsToRoomThreads() {
        guard shouldApplyBlockedAuthorFilter else { return }
        replaceMessages(messages)
        for (channelID, cache) in channelCaches {
            var updated = cache
            updated.messages = filterMessagesForBlockedAuthors(cache.messages)
            channelCaches[channelID] = updated
        }
    }

    private func removeMessage(id: MessageID) {
        messages = ConversationMessageMerge.mergeMessages(
            existing: messages.filter { $0.id != id },
            incoming: [],
            viewerID: viewerID
        )
        sendStates.removeValue(forKey: id)
    }

    private func sendVoice(data: Data, duration: TimeInterval) async {
        guard let viewerID, canPostInSelectedChannel, let channelID = selectedChannelID else { return }
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

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            sendStates[tempID] = .sent
            persistActiveChannelCache(scrollAnchor: tempID)
            patchInboxPreview(with: optimistic)
            return
        }

        do {
            let path = "\(viewerID.rawValue)/rooms/\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
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

            let payload = RoomMessage(
                id: RoomMessageID(tempID.rawValue),
                roomID: roomID,
                senderProfileID: viewerID,
                body: nil,
                attachedTradeID: nil,
                media: [MediaReference(id: resolvedURL, kind: .audio, altText: String(duration))],
                parentMessageID: nil,
                channelID: channelID,
                isPinned: false,
                createdAt: .now
            )
            let savedRoom = try await rooms.send(payload)
            let saved = RoomMessageMapping.displayMessage(from: savedRoom)
            commitMessages([saved])
            sendStates.removeValue(forKey: tempID)
            sendStates[saved.id] = .sent
            persistActiveChannelCache(scrollAnchor: saved.id)
            patchInboxPreview(with: saved)
            ExperienceHaptics.play(.messageSent)
        } catch {
            await handleSendFailure(
                tempID: tempID,
                optimistic: optimistic,
                channelID: channelID,
                content: nil,
                error: error
            )
        }
    }

    private func send(body: String, imageURL: String?, localImageData: Data?) async {
        guard let viewerID, canPostInSelectedChannel, let channelID = selectedChannelID else { return }
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

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            sendStates[tempID] = .sent
            persistActiveChannelCache(scrollAnchor: tempID)
            patchInboxPreview(with: optimistic)
            return
        }

        await completeOptimisticRoomImageSend(
            tempID: tempID,
            body: body,
            imageURL: imageURL,
            localImageData: localImageData,
            channelID: channelID,
            optimistic: optimistic
        )
    }

    private func resendFailedOptimisticImage(
        tempID: MessageID,
        body: String,
        localImageData: Data,
        channelID: RoomChannelID,
        optimisticCreatedAt: Date
    ) async {
        guard let viewerID, canPostInSelectedChannel else { return }
        sendStates[tempID] = .sending
        let optimistic = Message(
            id: tempID,
            conversationID: conversationID,
            senderProfileID: viewerID,
            kind: .media,
            body: body.isEmpty ? nil : body,
            attachments: OptimisticOutboundImageSendSupport.prepareOptimisticAttachments(
                tempID: tempID,
                localImageData: localImageData
            ),
            replyToMessageID: nil,
            createdAt: optimisticCreatedAt,
            isReadByViewer: true
        )
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            sendStates[tempID] = .sent
            return
        }
        await completeOptimisticRoomImageSend(
            tempID: tempID,
            body: body,
            imageURL: nil,
            localImageData: localImageData,
            channelID: channelID,
            optimistic: optimistic
        )
    }

    private func completeOptimisticRoomImageSend(
        tempID: MessageID,
        body: String,
        imageURL: String?,
        localImageData: Data?,
        channelID: RoomChannelID,
        optimistic: Message
    ) async {
        guard let viewerID else { return }
        var reconcileContent = body
        do {
            var resolvedImageURL = imageURL
            if let localImageData {
                let path = "\(viewerID.rawValue)/rooms/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
                resolvedImageURL = try await OptimisticOutboundImageSendSupport.uploadJPEG(
                    localImageData: localImageData,
                    storagePath: path,
                    uploadService: uploadService,
                    objectStorage: objectStorage
                )
            }

            let content: String = {
                if let resolvedImageURL, body.isEmpty { return resolvedImageURL }
                if let resolvedImageURL { return body.isEmpty ? resolvedImageURL : body }
                return body
            }()
            reconcileContent = content
            let payload = RoomMessage(
                id: RoomMessageID(tempID.rawValue),
                roomID: roomID,
                senderProfileID: viewerID,
                body: content,
                attachedTradeID: nil,
                media: resolvedImageURL.map {
                    [MediaReference(id: $0, kind: .image, altText: nil)]
                } ?? [],
                parentMessageID: nil,
                channelID: channelID,
                isPinned: false,
                createdAt: .now
            )
            #if DEBUG
            print(
                """
                [RoomMessageSend] compose roomID=\(roomID.rawValue) \
                channelID=\(channelID.rawValue) membershipJoined=\(membership != nil) \
                isOwner=\(isOwner)
                """
            )
            #endif
            let savedRoom = try await rooms.send(payload)
            let saved = RoomMessageMapping.displayMessage(from: savedRoom)
            commitMessages([saved])
            OptimisticOutboundImageStore.shared.remove(messageID: tempID)
            sendStates.removeValue(forKey: tempID)
            sendStates[saved.id] = .sent
            persistActiveChannelCache(scrollAnchor: saved.id)
            patchInboxPreview(with: saved)
            ExperienceHaptics.play(.messageSent)
        } catch {
            await handleSendFailure(
                tempID: tempID,
                optimistic: optimistic,
                channelID: channelID,
                content: reconcileContent,
                error: error
            )
        }
    }

    private func isSendCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let app = error as? AppError {
            switch app {
            case .cancelled:
                return true
            case .transport(.cancelled):
                return true
            default:
                break
            }
        }
        return NetworkTaskCancellation.mapIfCancelled(error) != nil
    }

    private func reconcileOptimisticSend(
        tempID: MessageID,
        sentAt: Date,
        content: String?,
        channelID: RoomChannelID
    ) async -> Message? {
        guard let viewerID else { return nil }
        let normalizedContent = content ?? ""
        do {
            let channel = channels.first { $0.id == channelID }
            let page = try await rooms.messages(
                roomID: roomID,
                channel: channel,
                page: PageRequest(limit: 20)
            )
            if let match = page.items.first(where: { message in
                message.senderProfileID == viewerID
                    && (message.body ?? "") == normalizedContent
                    && abs(message.createdAt.timeIntervalSince(sentAt)) < 45
            }) {
                #if DEBUG
                RoomMessageSendProbe.logReconciled(
                    RoomMessageSendProbe.Context(
                        roomID: roomID.rawValue,
                        channelID: channelID.rawValue,
                        senderID: viewerID.rawValue,
                        messageType: "reconcile",
                        hasReply: false
                    ),
                    messageID: match.id.rawValue
                )
                #endif
                return RoomMessageMapping.displayMessage(from: match)
            }
        } catch {
            // Soft-fail — caller may mark failed or retry.
        }
        return nil
    }

    private func handleSendFailure(
        tempID: MessageID,
        optimistic: Message,
        channelID: RoomChannelID,
        content: String?,
        error: Error
    ) async {
        if isSendCancellation(error) {
            sendStates.removeValue(forKey: tempID)
            return
        }
        if let reconciled = await reconcileOptimisticSend(
            tempID: tempID,
            sentAt: optimistic.createdAt,
            content: content,
            channelID: channelID
        ) {
            commitMessages([reconciled])
            OptimisticOutboundImageStore.shared.remove(messageID: tempID)
            sendStates.removeValue(forKey: tempID)
            sendStates[reconciled.id] = .sent
            persistActiveChannelCache(scrollAnchor: reconciled.id)
            patchInboxPreview(with: reconciled)
            ExperienceHaptics.play(.messageSent)
            return
        }
        sendStates[tempID] = .failed
        ExperienceHaptics.play(.error)
    }

    private func hydrateSenders(for messages: [Message]) async {
        let ids = Array(Set(messages.map(\.senderProfileID)))
        var missing: [ProfileID] = []
        for id in ids {
            if senderProfiles[id] != nil { continue }
            if let cached = detailCache.profile(id: id) {
                mergeSenderProfiles([cached], source: "detailCache")
                continue
            }
            if id.rawValue.hasPrefix("dev."),
               let fixture = FollowListFixtures.profile(id: id)
            {
                detailCache.seed(fixture)
                mergeSenderProfiles([fixture], source: "fixture")
                continue
            }
            missing.append(id)
        }
        guard !missing.isEmpty else { return }
        do {
            let fetched = try await SessionProfileStore.shared.profiles(
                ids: missing,
                detailCache: detailCache,
                repository: profiles
            )
            mergeSenderProfiles(fetched, source: "batch")
            let resolved = Set(fetched.map(\.id))
            for id in missing where !resolved.contains(id) {
                RoomSenderResolutionProbe.logUnresolved(
                    senderID: id,
                    reason: "profiles.batch returned no row"
                )
            }
        } catch {
            for id in missing {
                RoomSenderResolutionProbe.logUnresolved(
                    senderID: id,
                    reason: ConversationThreadSupport.message(for: error)
                )
            }
        }
    }

    private func mergeSenderProfiles(_ profiles: [Profile], source: String) {
        guard !profiles.isEmpty else { return }
        var merged = senderProfiles
        var changed = false
        for profile in profiles {
            detailCache.seed(profile)
            if merged[profile.id] != profile {
                merged[profile.id] = profile
                changed = true
            }
            RoomSenderResolutionProbe.logResolved(
                senderID: profile.id,
                source: source,
                username: profile.username,
                hasAvatar: profile.avatar != nil
            )
        }
        guard changed else { return }
        senderProfiles = merged
        senderProfileGeneration &+= 1
    }

    private func refreshInboxPreviewAfterDelete() {
        if let last = messages.last {
            patchInboxPreview(with: last)
        } else {
            inboxStore.replaceRooms(
                inboxStore.rooms,
                previews: [roomID: ""],
                activityAt: [:],
                unread: [roomID: 0]
            )
        }
    }

    private func patchInboxPreview(with message: Message) {
        let preview: String = {
            if message.kind == .tradeShare {
                return "Shared a trade"
            }
            if message.kind == .voice {
                return "Voice message"
            }
            if message.attachments.first?.media.kind == .audio {
                return "Voice message"
            }
            if message.attachments.isEmpty {
                return message.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "New message"
            }
            if message.attachments.first?.media.kind == .audio {
                return "Sent a voice message"
            }
            return message.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Sent a photo"
        }()
        inboxStore.replaceRooms(
            inboxStore.rooms.contains(where: { $0.id == roomID })
                ? inboxStore.rooms
                : (room.map { inboxStore.rooms + [$0] } ?? inboxStore.rooms),
            previews: [roomID: preview],
            activityAt: [roomID: message.createdAt],
            unread: [roomID: 0]
        )
    }

    private func findReaction(
        messageID: MessageID,
        viewerID: ProfileID,
        emoji: String
    ) -> RoomMessageReaction? {
        messages.first(where: { $0.id == messageID })?
            .roomReactions
            .first(where: { $0.userID == viewerID && $0.reaction == emoji })
    }

    private func isMessageVisible(_ messageID: String) -> Bool {
        if messages.contains(where: { $0.id.rawValue == messageID }) {
            return true
        }
        return channelCaches.values.contains { cache in
            cache.messages.contains(where: { $0.id.rawValue == messageID })
        }
    }

    private func applyReactionRealtime(
        _ event: MessageRealtimeSignal.ReactionEvent,
        kind: MessageRealtimeSignal.Kind
    ) {
        guard isMessageVisible(event.messageID) else { return }
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
        mode: RoomMessageReactionSemantics.PatchMode
    ) {
        func patchList(_ list: [Message]) -> [Message] {
            list.map { message in
                guard message.id == messageID else { return message }
                var updated = message
                updated.roomReactions = MessageReactionSemantics.patch(
                    message.roomReactions,
                    next: row,
                    mode: mode
                )
                return updated
            }
        }

        messages = patchList(messages)
        if let selectedChannelID {
            if var cache = channelCaches[selectedChannelID] {
                cache.messages = patchList(cache.messages)
                channelCaches[selectedChannelID] = cache
            }
        }
        for (channelID, cache) in channelCaches where channelID != selectedChannelID {
            guard cache.messages.contains(where: { $0.id == messageID }) else { continue }
            var updated = cache
            updated.messages = patchList(cache.messages)
            channelCaches[channelID] = updated
        }
    }

    private func buildTimeline(from messages: [Message]) -> [ConversationTimelineItem] {
        _ = senderProfileGeneration
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
            let startsSenderGroup = ConversationThreadSupport.tradeRoomStartsSenderGroup(
                message: message,
                previous: previous
            )
            let showsAvatar = !isOutgoing && startsSenderGroup
            let showsAuthorName = showsAvatar
            let showsTimestamp = next.map { $0.senderProfileID != message.senderProfileID } ?? true
            items.append(
                .message(
                    ConversationBubbleItem(
                        id: message.id,
                        message: message,
                        isOutgoing: isOutgoing,
                        showsAvatar: showsAvatar,
                        showsTimestamp: showsTimestamp,
                        sendState: sendStates[message.id] ?? .sent,
                        authorProfile: senderProfile(for: message.senderProfileID),
                        showsAuthorName: showsAuthorName,
                        authorTags: tagStore.tags(
                            for: message.senderProfileID,
                            roomID: roomID
                        ),
                        showsOwnerBadge: room?.ownerProfileID == message.senderProfileID,
                        startsSenderGroup: startsSenderGroup,
                        addsSenderGroupTopInset: previous != nil && startsSenderGroup
                    )
                )
            )
        }
        return items
    }

    private func reloadMessagesAfterMembershipGranted() async throws {
        guard canViewMessages, let channelID = selectedChannelID else { return }
        channelCaches.removeValue(forKey: channelID)
        try await fetchChannelMessages(channelID)
    }

    private func isAlreadyPendingJoinError(_ error: Error) -> Bool {
        let message = ConversationThreadSupport.message(for: error).lowercased()
        return message.contains("pending") || message.contains("already")
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
