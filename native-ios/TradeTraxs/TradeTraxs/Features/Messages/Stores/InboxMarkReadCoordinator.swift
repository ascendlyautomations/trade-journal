import Foundation

/// Shared inbox open → mark-read pipeline for DMs and Trade Rooms.
///
/// Used by inbox taps, Trade Rooms home, and push / deep-link navigation through
/// ``NavigationCoordinator/pushMessages`` so every entry path shares one flow:
/// optimistic inbox clear → RPC → mirror backend BadgeService onto the app icon.
@MainActor
final class InboxMarkReadCoordinator {
    static let shared = InboxMarkReadCoordinator()

    private var messages: (any MessageRepository)?
    private var rooms: (any RoomRepository)?
    private var session: (any SessionProviding)?

    private init() {}

    func configure(
        messages: any MessageRepository,
        rooms: any RoomRepository,
        session: any SessionProviding
    ) {
        self.messages = messages
        self.rooms = rooms
        self.session = session
    }

    /// Optimistic inbox clear + RPC — badge mirrors server after the cursor advances.
    func prepareOpenConversation(_ conversationID: ConversationID) {
        MessagesInboxStore.shared.markRead(conversationID: conversationID)
        Task { await confirmConversationRead(conversationID) }
    }

    func prepareOpenRoom(_ roomID: RoomID) {
        MessagesInboxStore.shared.markRoomRead(roomID: roomID)
        Task { await confirmRoomRead(roomID) }
    }

    /// Inbox swipe / menu — mark read with server + badge sync.
    func markConversationReadFromInbox(_ conversationID: ConversationID) {
        MessagesInboxStore.shared.markRead(conversationID: conversationID)
        Task { await confirmConversationRead(conversationID) }
    }

    /// Inbox swipe / menu — mark unread with server + badge sync.
    func markConversationUnreadFromInbox(_ conversationID: ConversationID) {
        MessagesInboxStore.shared.markUnread(conversationID: conversationID)
        Task { await confirmConversationUnread(conversationID) }
    }

    private func confirmConversationRead(_ conversationID: ConversationID) async {
        guard let messages, let session else { return }
        guard let userID = await session.currentUserID else { return }
        let viewer = ProfileID(userID.rawValue)
        guard !MessagesInboxSupport.isLocalDevelopmentProfile(viewer) else { return }
        do {
            try await messages.markRead(conversationID: conversationID)
            MessagesInboxStore.shared.markRead(conversationID: conversationID)
            AppIconBadgeSync.refresh(animated: false)
        } catch {
            // Drop optimistic override so the next inbox refresh shows server unread.
            MessagesInboxStore.shared.dropUnreadOverride(conversationID: conversationID)
            AppLog.notifications.error(
                "mark_conversation_read failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func confirmConversationUnread(_ conversationID: ConversationID) async {
        guard let messages, let session else { return }
        guard let userID = await session.currentUserID else { return }
        let viewer = ProfileID(userID.rawValue)
        guard !MessagesInboxSupport.isLocalDevelopmentProfile(viewer) else { return }
        do {
            try await messages.markUnread(conversationID: conversationID)
            MessagesInboxStore.shared.markUnread(conversationID: conversationID)
            AppIconBadgeSync.refresh(animated: false)
        } catch {
            MessagesInboxStore.shared.dropUnreadOverride(conversationID: conversationID)
            AppLog.notifications.error(
                "mark_conversation_unread failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func confirmRoomRead(_ roomID: RoomID) async {
        guard let rooms, let session else { return }
        guard let userID = await session.currentUserID else { return }
        let viewer = ProfileID(userID.rawValue)
        guard !MessagesInboxSupport.isLocalDevelopmentProfile(viewer) else { return }
        try? await rooms.markRead(roomID: roomID)
        MessagesInboxStore.shared.markRoomRead(roomID: roomID)
        // Room unread is not part of the app-icon formula — no badge fetch required.
    }
}
