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
            var member_count: PostgresFlexibleInt?
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
        var suggestions = rows.compactMap { row -> ExploreRoomSuggestion? in
            guard let id = row.id, let name = row.name else { return nil }
            let slug = (row.slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.lowercased() == "tradetraxs-beta" { return nil }
            return ExploreRoomSuggestion(
                id: RoomID(id),
                name: name,
                slug: slug.isEmpty ? id : slug,
                description: row.description,
                memberCount: row.member_count.map(\.value),
                imageURL: nil
            )
        }
        suggestions = try await attachRoomDisplayImages(to: suggestions)
        if suggestions.contains(where: { $0.memberCount == nil }) {
            suggestions = try await enrichRoomMemberCounts(suggestions)
        }
        return suggestions
    }

    private func enrichRoomMemberCounts(
        _ suggestions: [ExploreRoomSuggestion]
    ) async throws -> [ExploreRoomSuggestion] {
        guard !suggestions.isEmpty else { return suggestions }
        let counts = try await DefaultRoomRepository(supabase: supabase)
            .activeMemberCounts(for: suggestions.map(\.id))
        guard !counts.isEmpty else { return suggestions }
        return suggestions.map { suggestion in
            guard let count = counts[suggestion.id] else { return suggestion }
            var copy = suggestion
            copy.memberCount = count
            return copy
        }
    }

    /// Web `attachRoomImages` + `resolveRoomAvatarUrl`: room `image_url` first, owner avatar fallback.
    private func attachRoomDisplayImages(
        to suggestions: [ExploreRoomSuggestion]
    ) async throws -> [ExploreRoomSuggestion] {
        guard !suggestions.isEmpty else { return suggestions }

        struct RoomImageRow: Decodable {
            var id: String?
            var image_url: String?
            var owner_user_id: String?
        }

        let roomIDs = suggestions.map(\.id.rawValue)
        let roomRows: [RoomImageRow] = try await supabase.database.select(
            RoomImageRow.self,
            from: "rooms",
            query: [
                SupabaseQuery.select("id,image_url,owner_user_id"),
                SupabaseQuery.isIn("id", roomIDs),
            ]
        )

        var roomImageByID: [String: String] = [:]
        var ownerIDs = Set<String>()
        for row in roomRows {
            guard let id = row.id else { continue }
            if let image = row.image_url?.trimmingCharacters(in: .whitespacesAndNewlines),
               !image.isEmpty {
                roomImageByID[id] = image
            }
            if let owner = row.owner_user_id?.trimmingCharacters(in: .whitespacesAndNewlines),
               !owner.isEmpty {
                ownerIDs.insert(owner)
            }
        }

        var ownerAvatarByID: [String: String] = [:]
        if !ownerIDs.isEmpty {
            let profiles: [ProfileDTO.Profile] = try await supabase.database.select(
                ProfileDTO.Profile.self,
                from: "profiles",
                query: [
                    SupabaseQuery.select("id,avatar_url"),
                    SupabaseQuery.isIn("id", Array(ownerIDs)),
                ]
            )
            for profile in profiles {
                guard let id = profile.id,
                      let avatar = profile.avatar_url?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !avatar.isEmpty
                else { continue }
                ownerAvatarByID[id] = avatar
            }
        }

        var ownerByRoomID: [String: String] = [:]
        for row in roomRows {
            guard let id = row.id,
                  let owner = row.owner_user_id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !owner.isEmpty
            else { continue }
            ownerByRoomID[id] = owner
        }

        var sourceCounts: [String: Int] = [:]
        let resolved = suggestions.map { suggestion -> ExploreRoomSuggestion in
            var copy = suggestion
            if let roomImage = roomImageByID[suggestion.id.rawValue] {
                copy.imageURL = roomImage
                sourceCounts["roomImage", default: 0] += 1
            } else if let existing = suggestion.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !existing.isEmpty {
                copy.imageURL = existing
                sourceCounts["roomImage", default: 0] += 1
            } else if let owner = ownerByRoomID[suggestion.id.rawValue],
                      let ownerAvatar = ownerAvatarByID[owner] {
                copy.imageURL = ownerAvatar
                sourceCounts["ownerAvatar", default: 0] += 1
            } else {
                sourceCounts["missing", default: 0] += 1
            }
            return copy
        }

        #if DEBUG
        ExploreHydrationDiagnostics.logRooms(
            decoded: resolved.count,
            withImage: resolved.filter { $0.imageReference != nil }.count,
            sourceCounts: sourceCounts
        )
        #endif

        return resolved
    }

    func searchRooms(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        struct Row: Decodable {
            var id: String?
            var name: String?
            var description: String?
            var slug: String?
            var member_count: PostgresFlexibleInt?
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
        let suggestions = rows.compactMap { row -> ExploreRoomSuggestion? in
            guard let id = row.id, let name = row.name else { return nil }
            let slug = (row.slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.lowercased() == "tradetraxs-beta" { return nil }
            let image = row.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ExploreRoomSuggestion(
                id: RoomID(id),
                name: name,
                slug: slug.isEmpty ? id : slug,
                description: row.description,
                memberCount: row.member_count.map(\.value),
                imageURL: (image?.isEmpty == false) ? image : nil
            )
        }
        var resolved = try await attachRoomDisplayImages(to: suggestions)
        if resolved.contains(where: { $0.memberCount == nil }) {
            resolved = try await enrichRoomMemberCounts(resolved)
        }
        return resolved
    }
}
