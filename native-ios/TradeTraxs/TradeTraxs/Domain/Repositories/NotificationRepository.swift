import Foundation

nonisolated protocol NotificationRepository: Sendable {
    func notifications(page: PageRequest) async throws -> CursorPage<ActivityNotification>
    func unreadCount() async throws -> Int
    func markRead(id: NotificationID) async throws
    func markAllRead() async throws
}
