import Foundation
import Observation

@Observable
@MainActor
final class MessagesHomeViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var isRefreshing = false
    private(set) var isDeletingConversation = false
    private(set) var viewerID: ProfileID?
    var searchText = ""
    var showsNewChat = false
    /// Web `useDeleteChatConfirmation` pending id.
    var pendingDeleteConversationID: ConversationID?
    var showsDeleteConfirmation = false

    private let messages: any MessageRepository
    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let navigationCoordinator: NavigationCoordinator
    private let realtimeHub: RealtimeHub?

    private var loadTask: Task<Void, Never>?
    private var readCursorTask: Task<Void, Never>?
    private var roomUnreadTask: Task<Void, Never>?
    private var roomReadCursorTask: Task<Void, Never>?
    private var peerProfiles: [ProfileID: Profile] = [:]

    init(
        messages: any MessageRepository,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        inboxStore: MessagesInboxStore? = nil,
        realtimeHub: RealtimeHub? = nil
    ) {
        self.messages = messages
        self.rooms = rooms
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.inboxStore = inboxStore ?? MessagesInboxStore.shared
        self.realtimeHub = realtimeHub
    }

    var showsEmpty: Bool {
        phase == .loaded
            && inboxStore.visibleConversations.isEmpty
            && inboxStore.rooms.isEmpty
    }

    var showsFilteredEmpty: Bool {
        phase == .loaded
            && !showsEmpty
            && pinnedItems.isEmpty
            && directMessageItems.isEmpty
            && tradeRoomItems.isEmpty
    }

    var pinnedItems: [DirectMessageInboxItem] {
        filteredDirectMessages.filter(\.isPinned)
    }

    var directMessageItems: [DirectMessageInboxItem] {
        filteredDirectMessages.filter { !$0.isPinned }
    }

    var tradeRoomItems: [TradeRoomInboxItem] {
        let query = normalizedQuery
        let items = inboxStore.rooms.map(makeRoomItem)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.room.name.lowercased().contains(query)
                || $0.room.slug.lowercased().contains(query)
                || $0.preview.lowercased().contains(query)
        }
    }

    private var filteredDirectMessages: [DirectMessageInboxItem] {
        let items = inboxStore.visibleConversations.map(makeDMItem)
        let query = normalizedQuery
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.displayName.lowercased().contains(query)
                || ($0.username?.lowercased().contains(query) ?? false)
                || $0.preview.lowercased().contains(query)
        }
    }

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func loadIfNeeded() {
        guard loadTask == nil else { return }
        if inboxStore.hasLoaded {
            loadTask = Task {
                if viewerID == nil {
                    let current = await session.currentUserID
                    viewerID = current.map { ProfileID($0.rawValue) }
                }
                hydratePeersFromCache()
                // Resolve any peers still missing from the session profile cache.
                await resolvePeers(for: inboxStore.conversations, viewerID: viewerID)
                phase = .loaded
                await registerRealtime()
                loadTask = nil
            }
            return
        }
        loadTask = Task { await performLoad(forceNetwork: false) }
    }

    func refresh() async {
        loadTask?.cancel()
        isRefreshing = true
        await performLoad(forceNetwork: true)
        isRefreshing = false
    }

    func openConversation(_ item: DirectMessageInboxItem) {
        ExperienceHaptics.play(.selection)
        // Web inbox open: optimistic unread clear, then `mark_conversation_read` RPC.
        inboxStore.markRead(conversationID: item.id)
        if let viewerID, !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            Task {
                try? await messages.markRead(conversationID: item.id)
                // Confirm local badge stays cleared after RPC (no full inbox reload).
                inboxStore.markRead(conversationID: item.id)
            }
        }
        navigationCoordinator.open(.messages(.thread(item.id)))
    }

    func openRoom(_ item: TradeRoomInboxItem) {
        ExperienceHaptics.play(.selection)
        // Web room open: optimistic unread clear, then `mark_room_read` RPC.
        inboxStore.markRoomRead(roomID: item.id)
        if let viewerID, !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            Task {
                try? await rooms.markRead(roomID: item.id)
                inboxStore.markRoomRead(roomID: item.id)
            }
        }
        navigationCoordinator.open(.messages(.room(item.id)))
    }

    func openSettings() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.profile(.settings(.notifications)))
    }

    func presentNewChat() {
        ExperienceHaptics.play(.selection)
        showsNewChat = true
    }

    func toggleMute(conversationID: ConversationID) {
        ExperienceHaptics.play(.selection)
        inboxStore.toggleMute(conversationID: conversationID)
    }

    func toggleRead(conversationID: ConversationID) {
        ExperienceHaptics.play(.selection)
        let unread = inboxStore.unreadCount(
            for: inboxStore.conversations.first { $0.id == conversationID }
                ?? Conversation(
                    id: conversationID,
                    participantProfileIDs: [],
                    title: nil,
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
        )
        if unread > 0 {
            inboxStore.markRead(conversationID: conversationID)
        } else {
            inboxStore.markUnread(conversationID: conversationID)
        }
    }

    /// Web swipe/menu delete — confirm first (`DELETE_CHAT_CONFIRM_COPY`).
    func requestDeleteConversation(id: ConversationID) {
        guard !isDeletingConversation else { return }
        ExperienceHaptics.play(.warning)
        pendingDeleteConversationID = id
        showsDeleteConfirmation = true
    }

    func cancelDeleteConversation() {
        guard !isDeletingConversation else { return }
        pendingDeleteConversationID = nil
        showsDeleteConfirmation = false
    }

    /// Web `handleDeleteConversation` — remove participant row, then drop from inbox.
    func confirmDeleteConversation() async {
        guard let id = pendingDeleteConversationID, !isDeletingConversation else { return }
        isDeletingConversation = true
        defer {
            isDeletingConversation = false
            pendingDeleteConversationID = nil
            showsDeleteConfirmation = false
        }

        if let viewerID,
           MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || id.rawValue.hasPrefix("dev-")
        {
            inboxStore.removeConversation(id: id)
            return
        }

        do {
            try await messages.deleteConversation(id: id)
            inboxStore.removeConversation(id: id)
            ExperienceHaptics.play(.selection)
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }

    func toggleMute(roomID: RoomID) {
        ExperienceHaptics.play(.selection)
        inboxStore.toggleMute(roomID: roomID)
    }

    func leaveRoom(id: RoomID) async {
        ExperienceHaptics.play(.warning)
        guard let viewerID else {
            inboxStore.removeRoom(id: id)
            return
        }
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || id.rawValue.hasPrefix("dev-")
        {
            inboxStore.removeRoom(id: id)
            return
        }
        do {
            try await rooms.leave(roomID: id, profileID: viewerID)
            inboxStore.removeRoom(id: id)
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }

    func handleCreatedConversation(_ conversation: Conversation) {
        inboxStore.upsertConversation(conversation)
        navigationCoordinator.open(.messages(.thread(conversation.id)))
    }

    // MARK: - Private

    private func performLoad(forceNetwork: Bool) async {
        if !forceNetwork, inboxStore.hasLoaded {
            phase = .loaded
            hydratePeersFromCache()
            await registerRealtime()
            loadTask = nil
            return
        }

        if phase != .loaded {
            phase = .loading
        }

        do {
            let current = await session.currentUserID
            let viewer = current.map { ProfileID($0.rawValue) }
            viewerID = viewer

            if let viewer, MessagesInboxSupport.isLocalDevelopmentProfile(viewer) {
                MessagesInboxFixtures.seedStore(inboxStore, viewerID: viewer)
                await cachePeers(
                    MessagesInboxFixtures.profiles(
                        for: inboxStore.conversations,
                        viewerID: viewer
                    )
                )
                phase = .loaded
                await registerRealtime()
                loadTask = nil
                return
            }

            async let conversationsPage = messages.conversations(page: PageRequest(limit: 100))
            let memberRooms: [TradeRoom]
            var roomUnread: [RoomID: Int] = [:]
            if let viewer {
                memberRooms = try await rooms.memberRooms(
                    for: viewer,
                    page: PageRequest(limit: 50)
                ).items
                roomUnread = (try? await rooms.unreadCounts(for: memberRooms.map(\.id))) ?? [:]
            } else {
                memberRooms = []
            }
            let conversations = try await conversationsPage.items

            inboxStore.replaceConversations(conversations)
            inboxStore.replaceRooms(memberRooms, unread: roomUnread)

            // Seed peer profiles from repository-embedded participant IDs when available.
            await resolvePeers(for: conversations, viewerID: viewer)
            phase = .loaded
            await registerRealtime()
        } catch {
            if inboxStore.hasLoaded {
                phase = .loaded
            } else {
                phase = .failed(MessagesInboxSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func resolvePeers(for conversations: [Conversation], viewerID: ProfileID?) async {
        let peerIDs = Set(conversations.compactMap { MessagesInboxSupport.peerID(in: $0, viewerID: viewerID) })
        var resolved: [Profile] = []
        for id in peerIDs {
            if let cached = detailCache.profile(id: id) {
                peerProfiles[id] = cached
                continue
            }
            do {
                let profile = try await profiles.profile(id: id)
                detailCache.seed(profile)
                peerProfiles[id] = profile
                resolved.append(profile)
            } catch {
                continue
            }
        }
        _ = resolved
    }

    private func cachePeers(_ profiles: [Profile]) async {
        for profile in profiles {
            detailCache.seed(profile)
            peerProfiles[profile.id] = profile
        }
    }

    private func hydratePeersFromCache() {
        for conversation in inboxStore.conversations {
            if let peerID = MessagesInboxSupport.peerID(in: conversation, viewerID: viewerID),
               let cached = detailCache.profile(id: peerID)
            {
                peerProfiles[peerID] = cached
            }
        }
    }

    private func registerRealtime() async {
        guard let realtimeHub else { return }
        let channel = RealtimeChannelID(kind: .conversation, topic: "inbox")
        try? await realtimeHub.subscriptions.subscribe(channel)
        await startReadCursorRealtimeIfNeeded()
        await startRoomUnreadRealtimeIfNeeded()
        await startRoomReadCursorRealtimeIfNeeded()
    }

    /// Another device / tab advances `conversation_member_preferences` — patch that row only.
    private func startReadCursorRealtimeIfNeeded() async {
        guard let realtimeHub,
              let viewerID,
              !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
        else { return }
        guard readCursorTask == nil else { return }

        readCursorTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchConversationReadCursors(
                userID: viewerID.rawValue,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let conversationID = ConversationID(rawID)
                guard let existing = inboxStore.conversations.first(where: { $0.id == conversationID })
                else { continue }
                let locallyCleared = inboxStore.unreadCount(for: existing) == 0
                // Single-conversation refresh — never reload the full inbox.
                if var updated = try? await messages.conversation(id: conversationID) {
                    // Keep optimistic local clear if the unread RPC is briefly lagging.
                    if locallyCleared {
                        updated.unreadCount = 0
                    }
                    inboxStore.applyConversationUpdate(updated)
                    if locallyCleared {
                        inboxStore.markRead(conversationID: conversationID)
                    }
                } else if locallyCleared {
                    inboxStore.markRead(conversationID: conversationID)
                }
            }
            readCursorTask = nil
        }
    }

    /// Inbound room messages while on Messages home — bump unread unless that room is open.
    private func startRoomUnreadRealtimeIfNeeded() async {
        guard let realtimeHub,
              let viewerID,
              !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
        else { return }
        guard roomUnreadTask == nil else { return }
        let roomIDs = inboxStore.rooms.map(\.id.rawValue)
        guard !roomIDs.isEmpty else { return }

        roomUnreadTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchMemberRoomMessages(
                roomIDs: roomIDs,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                guard signal.kind == .insert else { continue }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let roomID = RoomID(rawID)
                guard inboxStore.rooms.contains(where: { $0.id == roomID }) else { continue }
                guard inboxStore.activeRoomID != roomID else { continue }
                inboxStore.markRoomUnread(roomID: roomID)
            }
            roomUnreadTask = nil
        }
    }

    /// Another device advances `room_members.last_read_*` — patch that room only.
    private func startRoomReadCursorRealtimeIfNeeded() async {
        guard let realtimeHub,
              let viewerID,
              !MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
        else { return }
        guard roomReadCursorTask == nil else { return }

        roomReadCursorTask = Task { [weak self] in
            guard let self else { return }
            let token = await session.accessToken
            for await signal in realtimeHub.watchRoomReadCursors(
                userID: viewerID.rawValue,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                guard let rawID = signal.conversationID ?? signal.messageID else { continue }
                let roomID = RoomID(rawID)
                guard inboxStore.rooms.contains(where: { $0.id == roomID }) else { continue }
                let locallyCleared = (inboxStore.roomUnread[roomID] ?? 0) == 0
                if let counts = try? await rooms.unreadCounts(for: [roomID]),
                   let count = counts[roomID]
                {
                    inboxStore.setRoomUnread(roomID: roomID, count: locallyCleared ? 0 : count)
                } else if locallyCleared {
                    inboxStore.markRoomRead(roomID: roomID)
                }
            }
            roomReadCursorTask = nil
        }
    }

    private func makeDMItem(_ conversation: Conversation) -> DirectMessageInboxItem {
        let peerID = MessagesInboxSupport.peerID(in: conversation, viewerID: viewerID)
        let peer = peerID.flatMap { peerProfiles[$0] ?? detailCache.profile(id: $0) }
        let unread = inboxStore.unreadCount(for: conversation)
        let preview = conversation.lastMessagePreview?.trimmingCharacters(in: .whitespacesAndNewlines)
        let username: String? = {
            if conversation.isGroup { return nil }
            if let peerUsername = conversation.peerUsername, !peerUsername.isEmpty {
                return "@\(peerUsername)"
            }
            return peer.map { "@\($0.username)" }
        }()
        return DirectMessageInboxItem(
            conversation: conversation,
            peer: peer,
            displayName: conversation.title
                ?? peer?.displayName
                ?? peer?.username
                ?? "Conversation",
            username: username,
            preview: (preview?.isEmpty == false ? preview! : "No messages yet"),
            timestamp: conversation.lastMessageAt ?? conversation.updatedAt,
            unreadCount: unread,
            isMuted: conversation.isMuted || inboxStore.isMuted(conversation.id),
            isPinned: conversation.isPinned || inboxStore.isPinned(conversation.id),
            isTyping: inboxStore.isTyping(conversation.id),
            isOnline: peerID.map { inboxStore.isOnline($0) } ?? false,
            showsReadReceipt: unread == 0 && !(preview?.isEmpty ?? true)
        )
    }

    private func makeRoomItem(_ room: TradeRoom) -> TradeRoomInboxItem {
        let preview = inboxStore.roomPreviews[room.id]
            ?? room.description
            ?? "No messages yet"
        let owner = peerProfiles[room.ownerProfileID] ?? detailCache.profile(id: room.ownerProfileID)
        return TradeRoomInboxItem(
            room: room,
            ownerName: owner?.displayName,
            ownerIsVerified: owner?.isCreator == true,
            preview: preview,
            timestamp: room.createdAt,
            unreadCount: inboxStore.roomUnread[room.id] ?? 0,
            isMuted: inboxStore.isRoomMuted(room.id)
        )
    }
}
