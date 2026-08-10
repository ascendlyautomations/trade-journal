import Foundation

nonisolated protocol NotificationPreferencesRepository: Sendable {
    func preferences(for userID: ProfileID) async throws -> NotificationPreferences
    func update(
        _ patch: [NotificationPreferenceKey: Bool],
        for userID: ProfileID
    ) async throws -> NotificationPreferences
}
