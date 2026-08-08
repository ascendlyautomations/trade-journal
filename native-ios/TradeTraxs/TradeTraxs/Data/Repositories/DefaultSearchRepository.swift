import Foundation

nonisolated struct DefaultSearchRepository: SearchRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func search(
        query: String,
        kinds: Set<SearchResultKind>,
        page: PageRequest
    ) async throws -> CursorPage<SearchResult> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CursorPage(items: [], nextCursor: nil)
        }

        var results: [SearchResult] = []
        if kinds.isEmpty || kinds.contains(.profile) {
            let profiles: [ProfileDTO.Profile] = try await supabase.database.select(
                ProfileDTO.Profile.self,
                from: "profiles",
                query: [
                    SupabaseQuery.select("id,username,name"),
                    URLQueryItem(name: "or", value: "(username.ilike.*\(trimmed)*,name.ilike.*\(trimmed)*)"),
                    URLQueryItem(name: "limit", value: String(page.limit)),
                ]
            )
            results += profiles.compactMap { dto in
                guard let id = dto.id else { return nil }
                let title = dto.username ?? dto.name ?? id
                return SearchResult(
                    id: id,
                    kind: .profile,
                    title: title,
                    subtitle: dto.name,
                    profileID: ProfileID(id),
                    tradeID: nil,
                    roomID: nil,
                    postID: nil
                )
            }
        }

        if kinds.isEmpty || kinds.contains(.trade) {
            let trades: [TradeDTO.Trade] = try await supabase.database.select(
                TradeDTO.Trade.self,
                from: "trades",
                query: [
                    SupabaseQuery.select("id,ticker,user_id,is_public"),
                    URLQueryItem(name: "ticker", value: "ilike.*\(trimmed)*"),
                    URLQueryItem(name: "is_public", value: "eq.true"),
                    URLQueryItem(name: "limit", value: String(page.limit)),
                ]
            )
            results += trades.compactMap { dto in
                guard let id = dto.id, let ticker = dto.ticker else { return nil }
                return SearchResult(
                    id: id,
                    kind: .trade,
                    title: ticker,
                    subtitle: nil,
                    profileID: dto.user_id.map { ProfileID($0) },
                    tradeID: TradeID(id),
                    roomID: nil,
                    postID: nil
                )
            }
        }

        return CursorPage(items: Array(results.prefix(page.limit)), nextCursor: nil)
    }
}
