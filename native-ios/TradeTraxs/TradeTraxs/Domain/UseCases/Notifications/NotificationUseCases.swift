import Foundation

nonisolated protocol MarkNotificationReadUseCase: Sendable {
    func execute(id: NotificationID) async throws
}
