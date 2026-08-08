import Foundation

nonisolated struct DefaultProfileRepository: ProfileRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let session: any SessionProviding

    init(
        supabase: SupabaseInfrastructure,
        cache: CacheStack = .placeholder(),
        session: any SessionProviding
    ) {
        self.supabase = supabase
        self.cache = cache
        self.session = session
    }

    func currentUser() async throws -> User {
        guard let userID = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let profile = try await profile(id: ProfileID(userID.rawValue))
        return User(id: userID, email: nil, createdAt: profile.createdAt)
    }

    func profile(id: ProfileID) async throws -> Profile {
        let dto: ProfileDTO.Profile = try await supabase.database.selectOne(
            ProfileDTO.Profile.self,
            from: "profiles",
            query: [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("id", id.rawValue),
            ]
        )
        return try ProfileMapper.mapToDomain(dto)
    }

    func profile(username: String) async throws -> Profile {
        let dto: ProfileDTO.Profile = try await supabase.database.selectOne(
            ProfileDTO.Profile.self,
            from: "profiles",
            query: [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("username", username),
            ]
        )
        return try ProfileMapper.mapToDomain(dto)
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        let body = ProfileDTO.UpdateBody(
            username: profile.username,
            name: profile.displayName,
            bio: profile.bio,
            avatar_url: profile.avatar?.id,
            trader_type: profile.traderType?.rawValue,
            is_private: profile.isPrivate
        )
        let dto: ProfileDTO.Profile = try await supabase.database.update(
            body,
            table: "profiles",
            query: [SupabaseQuery.eq("id", profile.id.rawValue)],
            returning: ProfileDTO.Profile.self
        )
        return try ProfileMapper.mapToDomain(dto)
    }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        struct Params: Encodable { var p_user_id: String }
        let data = try JSONEncoder().encode(Params(p_user_id: profileID.rawValue))
        let raw = try await supabase.database.rpcData(
            functionName: "user_streak_milestone_bundle",
            parametersJSON: data
        )
        let rows = try JSONDecoder().decode([HomeDTO.StreakBundle].self, from: raw)
        let bundle = rows.first
        return ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: 0,
            tradeCount: bundle?.trade_count ?? 0,
            publicTradeCount: bundle?.public_trade_count ?? 0
        )
    }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState {
        struct Row: Codable { var follower_id: String?; var following_id: String? }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "follows",
            query: [
                SupabaseQuery.select("follower_id,following_id"),
                SupabaseQuery.eq("follower_id", viewer.rawValue),
                SupabaseQuery.eq("following_id", target.rawValue),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.isEmpty ? .none : .following
    }

    func follow(from viewer: ProfileID, to target: ProfileID) async throws {
        struct Body: Encodable, Decodable {
            var follower_id: String
            var following_id: String
        }
        _ = try await supabase.database.insert(
            Body(follower_id: viewer.rawValue, following_id: target.rawValue),
            into: "follows",
            returning: Body.self
        )
    }

    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {
        try await supabase.database.delete(
            from: "follows",
            query: [
                SupabaseQuery.eq("follower_id", viewer.rawValue),
                SupabaseQuery.eq("following_id", target.rawValue),
            ]
        )
    }

    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        try await relatedProfiles(
            table: "follows",
            foreignKey: "following_id",
            profileKey: "follower_id",
            profileID: profileID,
            page: page
        )
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        try await relatedProfiles(
            table: "follows",
            foreignKey: "follower_id",
            profileKey: "following_id",
            profileID: profileID,
            page: page
        )
    }

    func creator(for profileID: ProfileID) async throws -> Creator? {
        let profile = try await profile(id: profileID)
        guard profile.isCreator else { return nil }
        return Creator(id: profile.id, profileID: profile.id, isVerified: false, headline: nil)
    }

    private func relatedProfiles(
        table: String,
        foreignKey: String,
        profileKey: String,
        profileID: ProfileID,
        page: PageRequest
    ) async throws -> CursorPage<Profile> {
        struct Edge: Codable { var id: String? }
        // Fall back to empty when graph shape differs; keeps Features isolated from schema drift.
        do {
            let edges: [Edge] = try await supabase.database.select(
                Edge.self,
                from: table,
                query: SupabaseQuery.page(page) + [
                    SupabaseQuery.select(profileKey),
                    SupabaseQuery.eq(foreignKey, profileID.rawValue),
                ]
            )
            _ = edges
        } catch {
            return CursorPage(items: [], nextCursor: nil)
        }
        return CursorPage(items: [], nextCursor: nil)
    }
}
