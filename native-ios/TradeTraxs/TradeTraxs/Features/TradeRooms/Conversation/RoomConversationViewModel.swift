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
    private(set) var ownerProfile: Profile?
    private(set) var channels: [RoomChannel] = []
    private(set) var selectedChannelID: RoomChannelID?
    private(set) var messages: [Message] = []
    private(set) var senderProfiles: [ProfileID: Profile] = [:]
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
    private(set) var tradePickerTrades: [Trade] = []
    private(set) var isLoadingTradePicker = false
    private(set) var sharedTrades: [TradeID: Trade] = [:]

    /// Prefer resolved UUID after slug deep-link lookup.
    private var resolvedRoomID: RoomID { room?.id ?? roomID }
    private var pendingDeepLinkFocus: RoomNavigationFocusStore.Focus?

    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let notifications: (any NotificationRepository)?
    private let tradesRepo: (any TradeRepository)?
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
    private var loadTask: Task<Void, Never>?
    private var channelLoadTasks: [RoomChannelID: Task<Void, Never>] = [:]
    private var channelCaches: [RoomChannelID: ChannelThreadCache] = [:]
    private var channelMetadataCached = false
    private var isApplyingRealtime = false
    private var didMarkReadThisOpen = false

    init(
        roomID: RoomID,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        detailCache: DetailPresentationCache,
        trades: (any TradeRepository)? = nil,
        notifications: (any NotificationRepository)? = nil,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages,
        realtimeHub: RealtimeHub? = nil,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.roomID = roomID
        self.rooms = rooms
        self.profiles = profiles
        self.notifications = notifications
        self.tradesRepo = trades
        self.session = session
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
        self.realtimeHub = realtimeHub
        self.inboxStore = inboxStore ?? .shared
        self.pendingDeepLinkFocus = RoomNavigationFocusStore.shared.consume(for: roomID)
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

    var showsEmpty: Bool {
        phase == .loaded
            && selectedChannelID != nil
            && timeline.filter({
                if case .message = $0 { return true }
                return false
            }).isEmpty
    }

    var title: String {
        room?.name ?? "Trade Room"
    }

    var memberCountLabel: String {
        let count = room?.memberCount ?? 0
        return "\(ProfileDisplay.compactCount(count)) members"
    }

    var isMember: Bool {
        membership != nil
    }

    var isOwner: Bool {
        guard let viewerID, let room else { return false }
        return room.ownerProfileID == viewerID
    }

    var canCompose: Bool {
        guard selectedChannel != nil else { return false }
        if isOwner || isMember { return true }
        return false
    }

    var joinButtonTitle: String {
        if isOwner { return "Owner" }
        if isMember { return "Joined" }
        return "Join"
    }

    var isMuted: Bool {
        inboxStore.isRoomMuted(roomID)
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded else { return }
        loadTask = Task { await performInitialLoad() }
    }

    func retryLoad() {
        guard loadTask == nil else { return }
        phase = .idle
        channelCaches = [:]
        channelMetadataCached = false
        loadTask = Task { await performInitialLoad() }
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
            await hydrateSharedTrades(from: mapped)
        } catch {
            // Soft-fail older page.
        }
    }

    func startRealtime() {
        inboxStore.setActiveRoom(roomID)
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            // Register topic + join web-equivalent room postgres_changes. Remain idle — no polling.
            let channel = RealtimeChannelID(kind: .room, topic: roomID.rawValue)
            try? await realtimeHub?.subscriptions.subscribe(channel)
            let token = await session.accessToken
            guard let realtimeHub else { return }
            for await signal in realtimeHub.watchRoomMessages(roomID: roomID, accessToken: token) {
                guard !Task.isCancelled else { break }
                await applyRealtimeSignal(signal)
            }
        }
    }

    func stopRealtime() {
        if inboxStore.activeRoomID == roomID {
            inboxStore.setActiveRoom(nil)
        }
        realtimeTask?.cancel()
        realtimeTask = nil
        Task { [roomID, realtimeHub] in
            let channel = RealtimeChannelID(kind: .room, topic: roomID.rawValue)
            try? await realtimeHub?.subscriptions.unsubscribe(channel)
            await realtimeHub?.stopWatchingRoomMessages(roomID: roomID)
        }
        persistActiveChannelCache(scrollAnchor: messages.last?.id)
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
        await send(
            body: draft.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: nil,
            localImageData: data
        )
        draft = ""
    }

    func presentTradePicker() {
        ExperienceHaptics.play(.selection)
        showsTradePicker = true
    }

    func loadTradePickerIfNeeded() async {
        guard tradePickerTrades.isEmpty, !isLoadingTradePicker else { return }
        guard let viewerID else { return }
        isLoadingTradePicker = true
        defer { isLoadingTradePicker = false }
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            tradePickerTrades = TradeShareFixtures.sampleTrades(ownerID: viewerID)
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
            tradePickerTrades = page.items
        } catch {
            tradePickerTrades = []
        }
    }

    func sendTrade(_ trade: Trade) async {
        guard let viewerID, !isSending, let channelID = selectedChannelID else { return }
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
                attachedTradeID: trade.id,
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
            sharedTrades[trade.id] = trade
            persistActiveChannelCache(scrollAnchor: saved.id)
            patchInboxPreview(with: saved)
            ExperienceHaptics.play(.selection)
        } catch {
            sendStates[tempID] = .failed
            ExperienceHaptics.play(.warning)
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

    func toggleMute() {
        ExperienceHaptics.play(.selection)
        inboxStore.toggleMute(roomID: roomID)
    }

    func toggleMembership() async {
        guard let viewerID, !isOwner, !isJoining else { return }
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
            return
        }
        do {
            if membership == nil {
                membership = try await rooms.join(roomID: roomID, profileID: viewerID)
                if var room {
                    room.memberCount += 1
                    self.room = room
                }
            } else {
                try await rooms.leave(roomID: roomID, profileID: viewerID)
                membership = nil
                if var room {
                    room.memberCount = max(0, room.memberCount - 1)
                    self.room = room
                }
            }
        } catch {
            ExperienceHaptics.play(.warning)
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

        do {
            if let viewer,
               MessagesInboxSupport.isLocalDevelopmentProfile(viewer)
                || roomID.rawValue.hasPrefix("dev-")
            {
                await loadLocalFixtures(viewerID: viewer)
            } else {
                try await loadFromRepository()
            }
            // Web waits until messages finished loading, then `mark_room_read`.
            await markRoomSeenIfNeeded(force: false)
            phase = .loaded
            startRealtime()
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
        guard let page = try? await notifications.notifications(page: PageRequest(limit: 100)) else {
            return
        }
        let slug = room?.slug
        for item in page.items where !item.isRead {
            let isRoomKind = item.kind == .roomJoin || item.kind == .roomMention
            let mentionsRoom = item.body.contains(roomID.rawValue)
                || (slug.map { item.body.contains($0) } ?? false)
            // DB `room_message` often maps to `.system` — content match covers it.
            if isRoomKind || mentionsRoom {
                try? await notifications.markRead(id: item.id)
            }
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
        senderProfiles[owner.id] = owner

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

    private func loadFromRepository() async throws {
        if !channelMetadataCached || room == nil {
            let loaded = try await rooms.room(id: roomID)
            room = loaded
            let activeRoomID = loaded.id
            if let viewerID {
                membership = try? await rooms.membership(roomID: activeRoomID, profileID: viewerID)
            }
            if let cached = detailCache.profile(id: loaded.ownerProfileID) {
                ownerProfile = cached
                senderProfiles[cached.id] = cached
            } else if let owner = try? await SessionProfileStore.shared.profiles(
                ids: [loaded.ownerProfileID],
                detailCache: detailCache,
                repository: profiles
            ).first {
                ownerProfile = owner
                senderProfiles[owner.id] = owner
            }
            channels = try await rooms.channels(roomID: activeRoomID)
            channelMetadataCached = true
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
        try await fetchChannelMessages(channelID)
        applyPendingDeepLinkFocusHighlight()
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
        await hydrateSharedTrades(from: sorted)
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
        let fetched = (try? await SessionTradeEntityStore.shared.trades(
            ids: ids,
            detailCache: detailCache,
            repository: tradesRepo
        )) ?? []
        for trade in fetched {
            sharedTrades[trade.id] = trade
        }
    }

    /// Incremental apply from Realtime — never reloads the whole room.
    private func applyRealtimeSignal(_ signal: MessageRealtimeSignal) async {
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

        isApplyingRealtime = true
        defer { isApplyingRealtime = false }
        do {
            let page = try await rooms.messages(
                roomID: roomID,
                channel: channel,
                page: PageRequest(limit: 30)
            )
            let mapped = page.items.map(RoomMessageMapping.displayMessage)
            let beforeIDs = Set(messages.map(\.id))
            // Commit merge immediately — hydrate senders afterward (no await before write).
            commitMessages(mapped)
            let addedPeerMessages = mapped.contains {
                $0.senderProfileID != viewerID && !beforeIDs.contains($0.id)
            }
            await hydrateSenders(for: mapped)
            persistActiveChannelCache(scrollAnchor: messages.last?.id)
            await hydrateSharedTrades(from: mapped)
            if let last = messages.last {
                patchInboxPreview(with: last)
            }
            // Web: while the room is open, inbound inserts re-run `mark_room_read`.
            if addedPeerMessages {
                await markRoomSeenIfNeeded(force: true)
            }
        } catch {
            // Soft-fail event-driven hydrate.
        }
    }

    /// Sole write path for thread rows — web `mergeMessages` semantics.
    private func commitMessages(_ incoming: [Message]) {
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
        let remainingIDs = Set(messages.map(\.id))
        for tempID in previousTempIDs where !remainingIDs.contains(tempID) {
            sendStates.removeValue(forKey: tempID)
        }
    }

    private func replaceMessages(_ incoming: [Message]) {
        messages = ConversationMessageMerge.mergeMessages(
            existing: [],
            incoming: incoming,
            viewerID: viewerID
        )
    }

    private func removeMessage(id: MessageID) {
        messages = ConversationMessageMerge.mergeMessages(
            existing: messages.filter { $0.id != id },
            incoming: [],
            viewerID: viewerID
        )
        sendStates.removeValue(forKey: id)
    }

    private func send(body: String, imageURL: String?, localImageData: Data?) async {
        guard let viewerID, let channelID = selectedChannelID else { return }
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

        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) || roomID.rawValue.hasPrefix("dev-") {
            sendStates[tempID] = .sent
            persistActiveChannelCache(scrollAnchor: tempID)
            patchInboxPreview(with: optimistic)
            return
        }

        do {
            var resolvedImageURL = imageURL
            if let localImageData {
                let path = "\(viewerID.rawValue)/rooms/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
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
                    commitMessages([updated])
                }
            }

            let content: String = {
                if let resolvedImageURL, body.isEmpty { return resolvedImageURL }
                if let resolvedImageURL { return body.isEmpty ? resolvedImageURL : body }
                return body
            }()
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
            let savedRoom = try await rooms.send(payload)
            let saved = RoomMessageMapping.displayMessage(from: savedRoom)
            commitMessages([saved])
            sendStates.removeValue(forKey: tempID)
            sendStates[saved.id] = .sent
            persistActiveChannelCache(scrollAnchor: saved.id)
            patchInboxPreview(with: saved)
            ExperienceHaptics.play(.selection)
        } catch {
            sendStates[tempID] = .failed
            ExperienceHaptics.play(.warning)
        }
    }

    private func hydrateSenders(for messages: [Message]) async {
        let ids = Array(Set(messages.map(\.senderProfileID)))
        var missing: [ProfileID] = []
        for id in ids {
            if senderProfiles[id] != nil { continue }
            if let cached = detailCache.profile(id: id) {
                senderProfiles[id] = cached
                continue
            }
            if id.rawValue.hasPrefix("dev."),
               let fixture = FollowListFixtures.profile(id: id)
            {
                detailCache.seed(fixture)
                senderProfiles[id] = fixture
                continue
            }
            missing.append(id)
        }
        guard !missing.isEmpty else { return }
        let fetched = (try? await SessionProfileStore.shared.profiles(
            ids: missing,
            detailCache: detailCache,
            repository: profiles
        )) ?? []
        for profile in fetched {
            senderProfiles[profile.id] = profile
        }
    }

    private func patchInboxPreview(with message: Message) {
        let preview: String = {
            if message.kind == .tradeShare {
                return "Shared a trade"
            }
            if message.attachments.isEmpty {
                return message.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "New message"
            }
            return message.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Sent a photo"
        }()
        inboxStore.replaceRooms(
            inboxStore.rooms.contains(where: { $0.id == roomID })
                ? inboxStore.rooms
                : (room.map { inboxStore.rooms + [$0] } ?? inboxStore.rooms),
            previews: [roomID: preview],
            unread: [roomID: 0]
        )
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
                        sendState: sendStates[message.id] ?? .sent,
                        authorProfile: senderProfiles[message.senderProfileID],
                        showsAuthorName: showsAvatar
                    )
                )
            )
        }
        return items
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
