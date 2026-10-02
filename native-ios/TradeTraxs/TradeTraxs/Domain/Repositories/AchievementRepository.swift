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
    func save(_ achievement: Achievement, metadata: JSONValue?) async throws -> Achievement
    /// Deletes by canonical ``achievements.id`` (not ``achievement_posts.id``).
    func delete(id: AchievementID) async throws
    /// One query for withdrawal ↔ achievement linkage (parses `achievements.metadata`).
    func withdrawalAchievementLinks(for profileID: ProfileID) async throws -> [WithdrawalAchievementLinkRow]
}

extension AchievementRepository {
    func delete(id: AchievementID) async throws {}
}
