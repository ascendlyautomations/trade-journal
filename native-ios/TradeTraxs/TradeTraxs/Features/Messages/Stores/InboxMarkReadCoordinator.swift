import Foundation

/// Shared inbox open → mark-read pipeline for DMs and Trade Rooms.
///
/// Used by inbox taps, Trade Rooms home, and push / deep-link navigation through
/// ``NavigationCoordinator/pushMessages`` so every entry path shares one flow:
/// optimistic clear → fire-and-forget RPC → confirm local clear → refresh app icon badge.
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

    /// Optimistic clear + RPC — identical for inbox tap and push deep link.
    func prepareOpenConversation(_ conversationID: ConversationID) {
        MessagesInboxStore.shared.markRead(conversationID: conversationID)
        AppIconBadgeSync.refresh(animated: false)
        Task { await confirmConversationRead(conversationID) }
    }

    func prepareOpenRoom(_ roomID: RoomID) {
        MessagesInboxStore.shared.markRoomRead(roomID: roomID)
        AppIconBadgeSync.refresh(animated: false)
        Task { await confirmRoomRead(roomID) }
    }

    private func confirmConversationRead(_ conversationID: ConversationID) async {
        guard let messages, let session else { return }
        guard let userID = await session.currentUserID else { return }
        let viewer = ProfileID(userID.rawValue)
        guard !MessagesInboxSupport.isLocalDevelopmentProfile(viewer) else { return }
        try? await messages.markRead(conversationID: conversationID)
        MessagesInboxStore.shared.markRead(conversationID: conversationID)
        AppIconBadgeSync.refresh(animated: false)
    }

    private func confirmRoomRead(_ roomID: RoomID) async {
        guard let rooms, let session else { return }
        guard let userID = await session.currentUserID else { return }
        let viewer = ProfileID(userID.rawValue)
        guard !MessagesInboxSupport.isLocalDevelopmentProfile(viewer) else { return }
        try? await rooms.markRead(roomID: roomID)
        MessagesInboxStore.shared.markRoomRead(roomID: roomID)
        AppIconBadgeSync.refresh(animated: false)
    }
}
