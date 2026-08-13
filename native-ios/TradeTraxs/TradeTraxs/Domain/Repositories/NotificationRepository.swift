import Foundation

nonisolated protocol NotificationRepository: Sendable {
    func notifications(page: PageRequest) async throws -> CursorPage<ActivityNotification>
    /// Fetches a single notification by id (Realtime hydration).
    func notification(id: NotificationID) async throws -> ActivityNotification?
    func unreadCount() async throws -> Int
    func markRead(id: NotificationID) async throws
    func markAllRead() async throws
    /// Batch-load actor profiles for Activity rows (anti-N+1).
    func profiles(ids: [ProfileID]) async throws -> [Profile]
}
