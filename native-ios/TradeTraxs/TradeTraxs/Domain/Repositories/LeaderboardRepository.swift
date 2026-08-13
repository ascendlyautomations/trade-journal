import Foundation

/// Leaderboard data — same public trade set as web `GET /api/leaderboard/trades`.
///
/// Timeframe filtering is **client-side** (web `filterTradesForLeaderboardWindow`).
nonisolated protocol LeaderboardRepository: Sendable {
    /// Full public trade rows (cached). Force refresh on pull-to-refresh.
    func tradeRows(forceNetwork: Bool) async throws -> [LeaderboardTradeRow]

    /// Filter + rank the cached/fetched trade set for a window (no SQL timeframe params).
    func entries(
        window: LeaderboardWindow,
        interval: DateIntervalValue?,
        page: PageRequest
    ) async throws -> CursorPage<LeaderboardEntry>
}
