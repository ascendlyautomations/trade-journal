import Foundation

/// Production leaderboard — mirrors web:
/// 1) Load public trades once (`GET /api/leaderboard/trades`, RPC fallback)
/// 2) Filter client-side by window (`filterTradesForLeaderboardWindow`)
/// 3) Rank by total PnL (`buildLeaderboardRankings`)
nonisolated struct DefaultLeaderboardRepository: LeaderboardRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let tradeCache: LeaderboardTradeRowsCache

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        tradeCache: LeaderboardTradeRowsCache = .shared
    ) {
        self.supabase = supabase
        self.cache = cache
        self.tradeCache = tradeCache
    }

    func tradeRows(forceNetwork: Bool) async throws -> [LeaderboardTradeRow] {
        if !forceNetwork, let cached = await tradeCache.cachedRows() {
            return cached
        }

        let rows: [LeaderboardTradeRow]
        if let bff = try? await fetchViaBFF() {
            rows = bff
        } else if let keyset = try? await fetchViaKeysetRPC() {
            rows = keyset
        } else {
            rows = try await fetchViaOffsetRPC()
        }

        await tradeCache.store(rows)
        return rows
    }

    func entries(
        window: LeaderboardWindow,
        interval: DateIntervalValue?,
        page: PageRequest
    ) async throws -> CursorPage<LeaderboardEntry> {
        let trades = try await tradeRows(forceNetwork: false)
        return LeaderboardTradeWindowFilter.entries(
            from: trades,
            window: window,
            interval: interval,
            page: page
        )
    }

    // MARK: - Web `GET /api/leaderboard/trades`

    private func fetchViaBFF() async throws -> [LeaderboardTradeRow] {
        guard let transport = supabase.transport else {
            throw AppError.unknown(message: "Network transport unavailable")
        }
        let response = try await transport.send(
            host: .bff,
            path: "/api/leaderboard/trades",
            method: .get,
            requiresAuthentication: false
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: "Couldn't load leaderboard data. Please try again.")
        }
        let decoded = try JSONDecoder().decode([LeaderboardDTO.TradeRow].self, from: response.data)
        return decoded.compactMap(Self.mapDTO)
    }

    // MARK: - Web BFF fallbacks (same RPCs)

    private func fetchViaKeysetRPC() async throws -> [LeaderboardTradeRow] {
        var all: [LeaderboardTradeRow] = []
        var afterCreatedAt: String?
        var afterUserID: String?
        let pageSize = 1000

        while true {
            struct Params: Encodable {
                var p_after_created_at: String?
                var p_after_user_id: String?
                var p_limit: Int
            }
            let data = try JSONEncoder().encode(
                Params(
                    p_after_created_at: afterCreatedAt,
                    p_after_user_id: afterUserID,
                    p_limit: pageSize
                )
            )
            let raw: Data
            do {
                raw = try await supabase.database.rpcData(
                    functionName: "leaderboard_trade_rows_page",
                    parametersJSON: data
                )
            } catch {
                // PGRST202 / missing function — let caller try offset RPC.
                throw error
            }
            let batch = try JSONDecoder().decode([LeaderboardDTO.TradeRow].self, from: raw)
                .compactMap(Self.mapDTO)
            all.append(contentsOf: batch)
            guard batch.count >= pageSize, let last = batch.last else { break }
            afterCreatedAt = last.createdAt
            afterUserID = last.userID
        }
        return all
    }

    private func fetchViaOffsetRPC() async throws -> [LeaderboardTradeRow] {
        var all: [LeaderboardTradeRow] = []
        var offset = 0
        let pageSize = 1000

        while true {
            struct Params: Encodable {
                var p_offset: Int
                var p_limit: Int
            }
            let data = try JSONEncoder().encode(Params(p_offset: offset, p_limit: pageSize))
            let raw = try await supabase.database.rpcData(
                functionName: "leaderboard_trade_rows",
                parametersJSON: data
            )
            let batch = try JSONDecoder().decode([LeaderboardDTO.TradeRow].self, from: raw)
                .compactMap(Self.mapDTO)
            all.append(contentsOf: batch)
            if batch.count < pageSize { break }
            offset += pageSize
        }
        return all
    }

    private static func mapDTO(_ row: LeaderboardDTO.TradeRow) -> LeaderboardTradeRow? {
        guard let userID = row.user_id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty,
              let created = row.created_at?.trimmingCharacters(in: .whitespacesAndNewlines),
              !created.isEmpty
        else { return nil }
        return LeaderboardTradeRow(
            userID: userID,
            pnl: DecimalParser.parseFlexible(row.pnl),
            rr: DecimalParser.parseFlexible(row.rr),
            createdAt: created,
            accountType: row.account_type,
            mode: row.mode
        )
    }
}

/// Process-scoped trade-row cache (web `leaderboardSessionCache` soft paint).
actor LeaderboardTradeRowsCache {
    static let shared = LeaderboardTradeRowsCache()

    private var stored: [LeaderboardTradeRow]?
    private var fetchedAt: Date?

    func cachedRows() -> [LeaderboardTradeRow]? { stored }

    func store(_ rows: [LeaderboardTradeRow]) {
        stored = rows
        fetchedAt = Date()
    }

    func invalidate() {
        stored = nil
        fetchedAt = nil
    }
}
