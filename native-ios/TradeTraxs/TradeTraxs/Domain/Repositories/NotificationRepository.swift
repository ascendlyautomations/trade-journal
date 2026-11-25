import Foundation

nonisolated protocol NotificationRepository: Sendable {
    func notifications(page: PageRequest, filter: ActivityNotificationListFilter) async throws -> CursorPage<ActivityNotification>
    /// Fetches a single notification by id (Realtime hydration).
    func notification(id: NotificationID) async throws -> ActivityNotification?
    func unreadCount() async throws -> Int
    func markRead(id: NotificationID) async throws
    /// Marks unread inbox rows by id in one update, RLS enforces `user_id = auth.uid()`.
    func markRead(ids: [NotificationID]) async throws -> Int
    func markUnread(id: NotificationID) async throws
    /// Marks read inbox rows back to unread in one update.
    func markUnread(ids: [NotificationID]) async throws -> Int
    /// Web `markMessageNotificationsRead`, all unread `type=message` rows for the viewer.
    func markMessageNotificationsRead() async throws -> Int
    /// Web `markNotificationsReadForTarget({ kind: "room" })`.
    func markRoomNotificationsRead(roomID: RoomID, slug: String?) async throws -> Int
    func markAllRead() async throws
    /// Owner-scoped delete, RLS enforces `user_id = auth.uid()`.
    func delete(id: NotificationID) async throws
    func delete(ids: [NotificationID]) async throws -> Int
    /// Batch-load actor profiles for Activity rows (anti-N+1).
    func profiles(ids: [ProfileID]) async throws -> [Profile]
}

extension NotificationRepository {
    func notifications(page: PageRequest) async throws -> CursorPage<ActivityNotification> {
        try await notifications(page: page, filter: .all)
    }
}
