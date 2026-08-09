import Foundation

nonisolated protocol AchievementRepository: Sendable {
    /// - Parameter publicOnly: Visitor path — web `fetchVisibleProfileAchievements` (`is_public = true`).
    ///   Owner path uses full `ACHIEVEMENT_SELECT` without that filter.
    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement>
    func achievement(id: AchievementID) async throws -> Achievement
    func save(_ achievement: Achievement) async throws -> Achievement
}
