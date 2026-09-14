import Foundation

/// Legacy leaderboard repository — full trade corpus download retired.
///
/// Rankings are loaded via `rpc_v1_leaderboard_bootstrap` when `backendV2.leaderboard` is enabled.
nonisolated struct DefaultLeaderboardRepository: LeaderboardRepository {
    func tradeRows(forceNetwork: Bool) async throws -> [LeaderboardTradeRow] {
        _ = forceNetwork
        throw AppError.unknown(
            message: "Leaderboard trade corpus loading is retired. Enable backendV2.leaderboard."
        )
    }

    func entries(
        window: LeaderboardWindow,
        interval: DateIntervalValue?,
        page: PageRequest
    ) async throws -> CursorPage<LeaderboardEntry> {
        _ = (window, interval, page)
        throw AppError.unknown(message: "Leaderboard entries require V2 bootstrap.")
    }
}

/// Retained for session cache invalidation hooks — no longer stores full trade corpora.
actor LeaderboardTradeRowsCache {
    static let shared = LeaderboardTradeRowsCache()

    func invalidate() {}

    func cachedRows() async -> [LeaderboardTradeRow]? { nil }

    func store(_ rows: [LeaderboardTradeRow]) async {
        _ = rows
    }
}
