import Foundation
import Observation

/// Messages inbox screen owner — presentation + navigation over ``MessagingDomain``.
///
/// Initial network / realtime ownership lives in ``MessagingDomain`` (shared with Trade Rooms).
@Observable
@MainActor
final class MessagesHomeViewModel {
    typealias Phase = MessagingState.Phase

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
    private let domain: MessagingDomain

    private var loadTask: Task<Void, Never>?

    init(
        messages: any MessageRepository,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        inboxStore: MessagesInboxStore? = nil,
        realtimeHub: RealtimeHub? = nil,
        domain: MessagingDomain? = nil
    ) {
        self.messages = messages
        self.rooms = rooms
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.inboxStore = inboxStore ?? MessagesInboxStore.shared
        self.realtimeHub = realtimeHub
        self.domain = domain ?? .shared
        self.domain.configure(
            messages: messages,
            rooms: rooms,
            profiles: profiles,
            session: session,
            detailCache: detailCache,
            realtimeHub: realtimeHub
        )
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
        // Messages gear → Settings → Notifications → Messages (hierarchical back stack).
        navigationCoordinator.openSettings([.home, .notifications, .notificationsMessages])
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
        if phase != .loaded {
            phase = .loading
        }
        if forceNetwork {
            await domain.refreshHome()
        } else {
            await domain.bootstrapHomeIfNeeded(forceNetwork: false)
        }
        viewerID = domain.state.viewerID
        phase = domain.state.phase
        isRefreshing = domain.state.isRefreshing
        await domain.retainRealtime()
        loadTask = nil
    }

    private func makeDMItem(_ conversation: Conversation) -> DirectMessageInboxItem {
        let peerID = MessagesInboxSupport.peerID(in: conversation, viewerID: viewerID)
        let peer = peerID.flatMap { domain.profile(id: $0) }
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
        let owner = domain.profile(id: room.ownerProfileID)
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

/// Canonical screen name for the Messages inbox (Profile/Feed architecture parity).
typealias MessagesScreenViewModel = MessagesHomeViewModel

/// Conversation thread screen owner — pagination / composer remain thread-scoped.
typealias ConversationScreenViewModel = ConversationViewModel

