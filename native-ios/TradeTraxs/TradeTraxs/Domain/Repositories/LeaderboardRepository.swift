import Foundation

nonisolated protocol LeaderboardRepository: Sendable {
    func entries(
        window: LeaderboardWindow,
        interval: DateIntervalValue?,
        page: PageRequest
    ) async throws -> CursorPage<LeaderboardEntry>
}
