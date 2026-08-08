import Foundation

nonisolated protocol AchievementRepository: Sendable {
    func achievements(
        for profileID: ProfileID,
        page: PageRequest
    ) async throws -> CursorPage<Achievement>
    func achievement(id: AchievementID) async throws -> Achievement
    func save(_ achievement: Achievement) async throws -> Achievement
}
