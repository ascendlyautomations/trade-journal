import Foundation
import os

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
    ///
    /// When ``BackendV2FeatureFlag/messageThreads`` is enabled, thread bootstrap RPC owns
    /// `mark_conversation_read` on intentional cold open — no duplicate coordinator RPC.
    func prepareOpenConversation(_ conversationID: ConversationID) {
        MessagesInboxStore.shared.markRead(conversationID: conversationID)
        guard !BackendV2FeatureFlags.isEnabled(.messageThreads) else {
            ThreadMarkReadTelemetry.log(
                owner: "bootstrap",
                intent: "open",
                applied: false,
                conversationID: conversationID
            )
            return
        }
        Task { await confirmConversationRead(conversationID) }
    }

    func prepareOpenRoom(_ roomID: RoomID) {
        let previousUnread = MessagesInboxStore.shared.roomUnread[roomID] ?? 0
        MessagesInboxStore.shared.markRoomRead(roomID: roomID)
        Task { await confirmRoomRead(roomID, previousUnread: previousUnread) }
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
            ThreadMarkReadTelemetry.log(
                owner: "coordinator",
                intent: "open",
                applied: true,
                conversationID: conversationID
            )
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

    private func confirmRoomRead(_ roomID: RoomID, previousUnread: Int) async {
        guard let rooms, let session else { return }
        guard let userID = await session.currentUserID else { return }
        let viewer = ProfileID(userID.rawValue)
        guard !MessagesInboxSupport.isLocalDevelopmentProfile(viewer) else { return }
        do {
            try await rooms.markRead(roomID: roomID)
            MessagesInboxStore.shared.markRoomRead(roomID: roomID)
            // Room unread is not part of the app-icon formula — no badge fetch required.
        } catch {
            MessagesInboxStore.shared.dropRoomUnreadOverride(roomID: roomID)
            if previousUnread > 0 {
                MessagesInboxStore.shared.setRoomUnread(roomID: roomID, count: previousUnread)
            }
            AppLog.notifications.error(
                "mark_room_read failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
