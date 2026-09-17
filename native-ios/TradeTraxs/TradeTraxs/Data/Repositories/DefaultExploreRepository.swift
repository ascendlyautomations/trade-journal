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

    func discoverRooms(
        mode: TradeRoomDiscoveryMode,
        scope: TradeRoomDiscoveryScope,
        limit: Int
    ) async throws -> [ExploreRoomSuggestion] {
        guard mode.usesDiscoveryRPC else { return [] }
        let capped = max(1, min(limit, 50))
        do {
            return try await fetchDiscoveryRPC(mode: mode, scope: scope, limit: capped)
        } catch {
            let fallback = try await popularRooms(limit: capped)
            return filterDiscoveryRooms(fallback, scope: scope)
        }
    }

    func tradeRoomsHomeBootstrap(
        scope: TradeRoomDiscoveryScope,
        limit: Int
    ) async throws -> TradeRoomsHomeBootstrap {
        let capped = max(1, min(limit, 50))
        struct Meta: Decodable {
            var contract_version: String?
            var viewer_id: String?
        }
        struct DataBlock: Decodable {
            var scope: String?
            var your_rooms: [DiscoveryRoomRow]?
            var suggested: [DiscoveryRoomRow]?
            var popular: [DiscoveryRoomRow]?
        }
        struct Payload: Decodable {
            var meta: Meta?
            var data: DataBlock?
        }

        let body = try JSONSerialization.data(
            withJSONObject: [
                "p_limit": capped,
                "p_scope": scope.rpcValue,
            ],
            options: []
        )
        let data = try await supabase.database.rpcData(
            functionName: BackendV2Versioning.RPCName.tradeRoomsHomeBootstrap.rawValue,
            parametersJSON: body
        )
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        if let version = payload.meta?.contract_version {
            try BackendV2Versioning.assertContractVersion(version)
        }
        let viewerID = payload.meta?.viewer_id.flatMap { raw -> ProfileID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : ProfileID(trimmed)
        }
        let yourRaw = payload.data?.your_rooms ?? []
        let suggestedRaw = payload.data?.suggested ?? []
        let popularRaw = payload.data?.popular ?? []
        let yourRooms = mapDiscoveryRows(yourRaw, section: "your_rooms")
        let suggested = mapDiscoveryRows(suggestedRaw, section: "suggested")
        let popular = mapDiscoveryRows(popularRaw, section: "popular")
        return TradeRoomsHomeBootstrap(
            viewerID: viewerID,
            scope: scope,
            yourRooms: yourRooms,
            suggested: suggested,
            popular: popular
        )
    }

    private struct DiscoveryOwnerRow: Decodable {
        var id: String?
        var username: String?
        var name: String?
        var avatar_url: String?
    }

    private struct DiscoveryRoomRow: Decodable {
        var id: String?
        var name: String?
        var description: String?
        var slug: String?
        var member_count: PostgresFlexibleInt?
        var image_url: String?
        var followed_member_count: PostgresFlexibleInt?
        var room_kind: String?
        var discovery_tags: [String]?
        var join_policy: String?
        var viewer_join_request_status: String?
        var is_owner: Bool?
        var is_member: Bool?
        var owner: DiscoveryOwnerRow?
    }

    private func fetchDiscoveryRPC(
        mode: TradeRoomDiscoveryMode,
        scope: TradeRoomDiscoveryScope,
        limit: Int
    ) async throws -> [ExploreRoomSuggestion] {
        struct Payload: Decodable {
            struct Meta: Decodable { var contract_version: String? }
            struct DataBlock: Decodable { var rooms: [DiscoveryRoomRow]? }
            var meta: Meta?
            var data: DataBlock?
        }

        let body = try JSONSerialization.data(
            withJSONObject: [
                "p_mode": mode.rpcValue,
                "p_limit": limit,
                "p_scope": scope.rpcValue,
            ],
            options: []
        )
        let data = try await supabase.database.rpcData(
            functionName: BackendV2Versioning.RPCName.tradeRoomDiscovery.rawValue,
            parametersJSON: body
        )
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        if let version = payload.meta?.contract_version {
            try BackendV2Versioning.assertContractVersion(version)
        }
        return mapDiscoveryRows(payload.data?.rooms ?? [], section: mode.rawValue)
    }

    private func mapDiscoveryRows(
        _ rows: [DiscoveryRoomRow],
        section: String = "discovery"
    ) -> [ExploreRoomSuggestion] {
        let mapped = rows.compactMap { row -> ExploreRoomSuggestion? in
            guard let id = row.id, let name = row.name else {
                RoomDiscoveryProbe.logDropped(roomID: row.id, reason: "\(section)MissingIdOrName")
                return nil
            }
            let slug = (row.slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.lowercased() == "tradetraxs-beta" {
                RoomDiscoveryProbe.logDropped(roomID: id, reason: "\(section)BetaSlug")
                return nil
            }
            let image = row.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ownerID = row.owner?.id.flatMap { ProfileID($0) }
            return ExploreRoomSuggestion(
                id: RoomID(id),
                name: name,
                slug: slug.isEmpty ? id : slug,
                description: row.description,
                memberCount: row.member_count.map(\.value),
                imageURL: (image?.isEmpty == false) ? image : row.owner?.avatar_url,
                ownerProfileID: ownerID,
                ownerUsername: row.owner?.username,
                ownerDisplayName: row.owner?.name,
                ownerAvatarURL: row.owner?.avatar_url,
                followedMemberCount: row.followed_member_count.map(\.value),
                roomKind: TradeRoomKind.parse(row.room_kind),
                discoveryTags: row.discovery_tags ?? [],
                isJoined: row.is_member,
                isOwner: row.is_owner,
                isMember: row.is_member,
                joinPolicy: TradeRoomJoinPolicy(rawValue: row.join_policy ?? "") ?? .open,
                viewerJoinRequestState: TradeRoomJoinRequestState.parse(row.viewer_join_request_status)
            )
        }
        RoomDiscoveryProbe.logBootstrapSection(
            section: section,
            serverReturned: rows.count,
            decoded: mapped.count
        )
        return mapped
    }

    private func filterDiscoveryRooms(
        _ rooms: [ExploreRoomSuggestion],
        scope: TradeRoomDiscoveryScope
    ) -> [ExploreRoomSuggestion] {
        rooms.filter { room in
            guard room.slug.lowercased() != "tradetraxs-beta" else { return false }
            switch scope {
            case .all, .yourRooms: return true
            case .official: return room.isOfficial
            case .community: return !room.isOfficial
            }
        }
    }

    func popularRooms(limit: Int) async throws -> [ExploreRoomSuggestion] {
        struct Row: Decodable {
            var id: String?
            var name: String?
            var description: String?
            var slug: String?
            var member_count: PostgresFlexibleInt?
            var room_kind: String?
            var discovery_tags: [String]?
            var join_policy: String?
            var viewer_join_request_status: String?
            var image_url: String?
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
                imageURL: row.image_url,
                roomKind: TradeRoomKind.parse(row.room_kind),
                discoveryTags: row.discovery_tags ?? [],
                joinPolicy: TradeRoomJoinPolicy(rawValue: row.join_policy ?? "") ?? .open,
                viewerJoinRequestState: TradeRoomJoinRequestState.parse(row.viewer_join_request_status)
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

        let capped = max(1, min(limit, 50))
        do {
            return try await fetchSearchRPC(query: trimmed, limit: capped)
        } catch {
            return try await fetchLegacySearchRPC(query: trimmed, limit: capped)
        }
    }

    private func fetchSearchRPC(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] {
        struct RoomRow: Decodable {
            var id: String?
            var name: String?
            var description: String?
            var slug: String?
            var member_count: PostgresFlexibleInt?
            var image_url: String?
            var room_kind: String?
            var discovery_tags: [String]?
            var join_policy: String?
            var viewer_join_request_status: String?
            var is_member: Bool?
        }

        struct Payload: Decodable {
            struct Meta: Decodable { var contract_version: String? }
            struct DataBlock: Decodable { var rooms: [RoomRow]? }
            var meta: Meta?
            var data: DataBlock?
        }

        let body = try JSONSerialization.data(
            withJSONObject: [
                "p_query": query,
                "p_limit": limit,
            ],
            options: []
        )
        let data = try await supabase.database.rpcData(
            functionName: BackendV2Versioning.RPCName.tradeRoomSearch.rawValue,
            parametersJSON: body
        )
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        if let version = payload.meta?.contract_version {
            try BackendV2Versioning.assertContractVersion(version)
        }
        let rows = payload.data?.rooms ?? []
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
                imageURL: (image?.isEmpty == false) ? image : nil,
                roomKind: TradeRoomKind.parse(row.room_kind),
                discoveryTags: row.discovery_tags ?? [],
                isJoined: row.is_member,
                joinPolicy: TradeRoomJoinPolicy(rawValue: row.join_policy ?? "") ?? .open,
                viewerJoinRequestState: TradeRoomJoinRequestState.parse(row.viewer_join_request_status)
            )
        }
        var resolved = try await attachRoomDisplayImages(to: suggestions)
        if resolved.contains(where: { $0.memberCount == nil }) {
            resolved = try await enrichRoomMemberCounts(resolved)
        }
        return resolved
    }

    private func fetchLegacySearchRPC(query: String, limit: Int) async throws -> [ExploreRoomSuggestion] {
        struct Row: Decodable {
            var id: String?
            var name: String?
            var description: String?
            var slug: String?
            var member_count: PostgresFlexibleInt?
            var image_url: String?
        }

        let body = try JSONSerialization.data(
            withJSONObject: [
                "p_query": query,
                "p_limit": limit,
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
        return try await attachRoomDisplayImages(to: suggestions)
    }
}
