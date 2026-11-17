import Foundation

nonisolated protocol NotificationPreferencesRepository: Sendable {
    func preferences(for userID: ProfileID, forceRefresh: Bool) async throws -> NotificationPreferences
    func invalidateCachedPreferences(for userID: ProfileID)
    func update(
        _ patch: [NotificationPreferenceKey: Bool],
        for userID: ProfileID
    ) async throws -> NotificationPreferences
}

extension NotificationPreferencesRepository {
    func preferences(for userID: ProfileID) async throws -> NotificationPreferences {
        try await preferences(for: userID, forceRefresh: false)
    }
}
