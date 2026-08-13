import Foundation

nonisolated struct DefaultExploreRepository: ExploreRepository {
    private let supabase: SupabaseInfrastructure

    init(supabase: SupabaseInfrastructure) {
        self.supabase = supabase
    }

    func discoverableProfiles(page: PageRequest) async throws -> CursorPage<Profile> {
        let offset = Int(page.cursor ?? "0") ?? 0
        let limit = max(1, min(page.limit, 48))
        let rows: [ProfileDTO.Profile] = try await supabase.database.select(
            ProfileDTO.Profile.self,
            from: "profiles",
            query: [
                SupabaseQuery.select(
                    "id,username,name,bio,avatar_url,trader_type,trading_style,primary_market,started_trading,is_private,created_at"
                ),
                URLQueryItem(name: "username", value: "not.is.null"),
                URLQueryItem(name: "is_private", value: "neq.true"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        let profiles = rows.compactMap { try? ProfileMapper.mapToDomain($0) }
            .filter { !$0.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let next = profiles.count >= limit ? String(offset + limit) : nil
        return CursorPage(items: profiles, nextCursor: next)
    }

    func socialCounts(for profileIDs: [ProfileID]) async throws -> ExploreSocialCounts {
        let unique = Array(Set(profileIDs.map(\.rawValue))).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return .empty }

        struct Row: Decodable {
            var profile_id: String?
            var followers_count: Int?
            var following_count: Int?
        }

        let body = try JSONSerialization.data(
            withJSONObject: ["p_profile_ids": unique],
            options: []
        )
        do {
            let data = try await supabase.database.rpcData(
                functionName: "explore_social_counts",
                parametersJSON: body
            )
            let rows = try JSONDecoder().decode([Row].self, from: data)
            var followers: [ProfileID: Int] = [:]
            var following: [ProfileID: Int] = [:]
            for row in rows {
                guard let id = row.profile_id else { continue }
                let profileID = ProfileID(id)
                followers[profileID] = row.followers_count ?? 0
                following[profileID] = row.following_count ?? 0
            }
            return ExploreSocialCounts(followers: followers, following: following)
        } catch {
            return .empty
        }
    }

    func tradeActivitySummaries(limit: Int) async throws -> [ProfileID: ExploreTraderRanking.TradeSummary] {
        struct Row: Decodable {
            var row_kind: String?
            var user_id: String?
            var trade_count: Int?
            var last_trade_at: String?
        }

        let capped = max(1, min(limit, 3000))
        let body = try JSONSerialization.data(
            withJSONObject: ["p_limit": capped],
            options: []
        )
        do {
            let data = try await supabase.database.rpcData(
                functionName: "explore_trade_meta_aggregates",
                parametersJSON: body
            )
            let rows = try JSONDecoder().decode([Row].self, from: data)
            var map: [ProfileID: ExploreTraderRanking.TradeSummary] = [:]
            for row in rows where row.row_kind == "summary" {
                guard let userID = row.user_id else { continue }
                map[ProfileID(userID)] = ExploreTraderRanking.TradeSummary(
                    tradeCount: row.trade_count ?? 0,
                    lastTradeAt: ISO8601.date(from: row.last_trade_at)
                )
            }
            return map
        } catch {
            return [:]
        }
    }

    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] {
        struct Row: Decodable {
            var id: String?
            var name: String?
            var description: String?
            var slug: String?
            var member_count: Int?
        }

        let capped = max(1, min(limit, 50))
        let body = try JSONSerialization.data(
            withJSONObject: ["p_limit": capped],
            options: []
        )
        let data = try await supabase.database.rpcData(
            functionName: "popular_trade_rooms",
            parametersJSON: body
        )
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.compactMap { row in
            guard let id = row.id, let name = row.name else { return nil }
            let slug = (row.slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.lowercased() == "tradetraxs-beta" { return nil }
            return ExploreRoomSuggestion(
                id: RoomID(id),
                name: name,
                slug: slug.isEmpty ? id : slug,
                description: row.description,
                memberCount: row.member_count ?? 0,
                imageURL: nil
            )
        }
    }

    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        struct Row: Decodable {
            var id: String?
            var name: String?
            var description: String?
            var slug: String?
            var member_count: Int?
            var image_url: String?
        }

        let capped = max(1, min(limit, 50))
        let body = try JSONSerialization.data(
            withJSONObject: [
                "p_query": trimmed,
                "p_limit": capped,
            ],
            options: []
        )
        let data = try await supabase.database.rpcData(
            functionName: "search_public_trade_rooms",
            parametersJSON: body
        )
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.compactMap { row in
            guard let id = row.id, let name = row.name else { return nil }
            let slug = (row.slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.lowercased() == "tradetraxs-beta" { return nil }
            let image = row.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ExploreRoomSuggestion(
                id: RoomID(id),
                name: name,
                slug: slug.isEmpty ? id : slug,
                description: row.description,
                memberCount: row.member_count ?? 0,
                imageURL: (image?.isEmpty == false) ? image : nil
            )
        }
    }
}
