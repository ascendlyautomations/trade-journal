import Foundation

nonisolated struct DefaultLeaderboardRepository: LeaderboardRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func entries(
        window: LeaderboardWindow,
        interval: DateIntervalValue?,
        page: PageRequest
    ) async throws -> CursorPage<LeaderboardEntry> {
        _ = (window, interval)
        struct Params: Encodable {
            var p_offset: Int
            var p_limit: Int
        }
        let offset = page.cursor.flatMap(Int.init) ?? 0
        let data = try JSONEncoder().encode(Params(p_offset: offset, p_limit: page.limit))
        let raw = try await supabase.database.rpcData(
            functionName: "leaderboard_trade_rows",
            parametersJSON: data
        )
        let rows = try JSONDecoder().decode([LeaderboardDTO.TradeRow].self, from: raw)

        var aggregates: [String: (pnl: Decimal, count: Int)] = [:]
        for row in rows {
            guard let userID = row.user_id else { continue }
            let pnl = DecimalParser.parseFlexible(row.pnl) ?? 0
            let current = aggregates[userID] ?? (0, 0)
            aggregates[userID] = (current.pnl + pnl, current.count + 1)
        }

        let sorted = aggregates.sorted { $0.value.pnl > $1.value.pnl }
        let entries: [LeaderboardEntry] = sorted.enumerated().map { index, element in
            LeaderboardEntry(
                rank: offset + index + 1,
                profileID: ProfileID(element.key),
                username: element.key,
                totalPnL: Money(amount: element.value.pnl),
                tradeCount: element.value.count,
                averageRiskReward: nil
            )
        }
        let next = rows.count >= page.limit ? String(offset + page.limit) : nil
        return CursorPage(items: entries, nextCursor: next)
    }
}
