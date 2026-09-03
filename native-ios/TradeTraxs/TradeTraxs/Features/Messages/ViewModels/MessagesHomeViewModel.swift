import Foundation
import Observation
import OSLog

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
    var deleteConversationErrorMessage: String?
    /// Pending Trade Room leave confirmation.
    var pendingLeaveRoomID: RoomID?
    var showsLeaveRoomConfirmation = false

    private let messages: any MessageRepository
    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let navigationCoordinator: NavigationCoordinator
    private let realtimeHub: RealtimeHub?
    private let domain: MessagingDomain

    init(
        messages: any MessageRepository,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        inboxStore: MessagesInboxStore? = nil,
        realtimeHub: RealtimeHub? = nil,
        domain: MessagingDomain? = nil,
        rpc: (any RPCClient)? = nil
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
#if DEBUG
        SafeInboxLog.storeObserved(
            instance: self.inboxStore.debugInstance,
            source: "MessagesHomeViewModel"
        )
#endif
        self.domain.configure(
            messages: messages,
            rooms: rooms,
            profiles: profiles,
            session: session,
            detailCache: detailCache,
            realtimeHub: realtimeHub,
            rpc: rpc
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

    var canonicalInboxStore: MessagesInboxStore { inboxStore }

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
        Task { await bootstrapIfNeeded() }
    }

    func bootstrapIfNeeded() async {
        await domain.bootstrapHomeIfNeeded(forceNetwork: false)
        syncFromDomain()
        await domain.retainRealtime()
    }

    func setHomeScreenVisible(_ visible: Bool) {
        domain.setHomeScreenVisible(visible)
    }

    func refresh() async {
        isRefreshing = true
        await domain.refreshHome()
        syncFromDomain()
        isRefreshing = false
    }

    func openConversation(_ item: DirectMessageInboxItem) {
        ExperienceHaptics.play(.selection)
        // Mark-read runs inside ``NavigationCoordinator/pushMessages`` so push
        // deep links and inbox taps share one pipeline.
        navigationCoordinator.open(.messages(.thread(item.id)))
    }

    func openRoom(_ item: TradeRoomInboxItem) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.messages(.room(item.id)))
    }

    func openSettings() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushMessages(.settings(.home))
    }

    func presentNewChat() {
        ExperienceHaptics.play(.selection)
        showsNewChat = true
    }

    func toggleMute(conversationID: ConversationID) {
        ExperienceHaptics.play(.selection)
        Task { await setConversationMuted(conversationID: conversationID, muted: !inboxStore.isMuted(conversationID)) }
    }

    func setConversationMuted(conversationID: ConversationID, muted: Bool) async {
        let previous = inboxStore.isMuted(conversationID)
        guard previous != muted else { return }
        inboxStore.applyConversationMute(conversationID: conversationID, isMuted: muted)

        if let viewerID,
           MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || conversationID.rawValue.hasPrefix("dev-")
        {
            return
        }

        do {
            try await messages.setConversationNotificationsEnabled(
                conversationID: conversationID,
                enabled: !muted
            )
        } catch {
            inboxStore.applyConversationMute(conversationID: conversationID, isMuted: previous)
        }
    }

    func togglePin(conversationID: ConversationID) {
        ExperienceHaptics.play(.selection)
        inboxStore.togglePin(conversationID: conversationID)
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
                    updatedAt: .distantPast
                )
        )
        if unread > 0 {
            InboxMarkReadCoordinator.shared.markConversationReadFromInbox(conversationID)
        } else {
            InboxMarkReadCoordinator.shared.markConversationUnreadFromInbox(conversationID)
        }
    }

    /// Web swipe/menu delete — confirm first (`DELETE_CHAT_CONFIRM_COPY`).
    func requestDeleteConversation(id: ConversationID) {
        guard !isDeletingConversation else { return }
        ExperienceHaptics.play(.warning)
        pendingDeleteConversationID = id
        showsDeleteConfirmation = true
        AppLog.networking.debug(
            "conversations.delete.uiRequested id=\(SafeInboxLog.hash(id.rawValue), privacy: .public)"
        )
    }

    func cancelDeleteConversation() {
        guard !isDeletingConversation else { return }
        pendingDeleteConversationID = nil
        showsDeleteConfirmation = false
    }

    /// Web `handleDeleteConversation` — remove participant row, then drop from inbox.
    func confirmDeleteConversation() async {
        guard let id = pendingDeleteConversationID else { return }
        await confirmDeleteConversation(id: id)
    }

    func confirmDeleteConversation(id: ConversationID) async {
        guard !isDeletingConversation else { return }
        isDeletingConversation = true
        deleteConversationErrorMessage = nil
        showsDeleteConfirmation = false
        let snapshot = inboxStore.conversations.first { $0.id == id }
        AppLog.networking.debug(
            "conversations.delete.confirmed id=\(SafeInboxLog.hash(id.rawValue), privacy: .public)"
        )
        defer {
            isDeletingConversation = false
            pendingDeleteConversationID = nil
        }

        if let viewerID,
           MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || id.rawValue.hasPrefix("dev-")
        {
            inboxStore.removeConversation(id: id)
            return
        }

        inboxStore.removeConversation(id: id, pendingRemoteDelete: true)

        do {
            try await messages.deleteConversation(id: id)
            inboxStore.finalizeConversationDelete(id: id)
            if let viewerID {
                ConversationThreadSessionStore.shared.invalidate(
                    viewerID: viewerID,
                    conversationID: id
                )
            }
            ExperienceHaptics.play(.success)
        } catch {
            if let snapshot {
                inboxStore.restoreRemovedConversation(snapshot)
            } else {
                inboxStore.cancelPendingConversationDelete(id: id)
            }
            deleteConversationErrorMessage = UserFacingError.map(
                error as? AppError ?? AppError.unknown(message: error.localizedDescription)
            ).message
            ExperienceHaptics.play(.error)
        }
    }

    func toggleMute(roomID: RoomID) {
        ExperienceHaptics.play(.selection)
        inboxStore.toggleMute(roomID: roomID)
    }

    func requestLeaveRoom(id: RoomID) {
        ExperienceHaptics.play(.warning)
        pendingLeaveRoomID = id
        showsLeaveRoomConfirmation = true
    }

    func cancelLeaveRoom() {
        pendingLeaveRoomID = nil
        showsLeaveRoomConfirmation = false
    }

    func confirmLeaveRoom() async {
        guard let id = pendingLeaveRoomID else { return }
        pendingLeaveRoomID = nil
        showsLeaveRoomConfirmation = false
        await leaveRoom(id: id)
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
            ExperienceHaptics.play(.success)
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }

    func handleCreatedConversation(_ conversation: Conversation) {
        inboxStore.upsertConversation(conversation)
        #if DEBUG
        ConversationCreationTelemetry.navigationCompleted()
        #endif
        navigationCoordinator.open(.messages(.thread(conversation.id)))
    }

    // MARK: - Private

    private func syncFromDomain() {
        viewerID = domain.state.viewerID
        phase = domain.state.phase
        isRefreshing = domain.state.isRefreshing
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
            timestamp: conversation.lastMessageAt,
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

