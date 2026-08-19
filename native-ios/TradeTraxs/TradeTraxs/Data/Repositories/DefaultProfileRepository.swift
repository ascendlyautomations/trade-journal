import Foundation
import OSLog

nonisolated struct DefaultProfileRepository: ProfileRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack
    private let session: any SessionProviding

    /// Exact web Profile select from `app/profile/[id]/page.tsx` (`PUBLIC_PROFILE_SELECT`).
    /// Do not add columns the web does not request.
    private static let publicProfileSelect =
        "id,username,name,bio,avatar_url,trading_style,trader_type,primary_market,started_trading,is_private,created_at"

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
        let cacheKey = "profile:\(id.rawValue)"
        if let cached = cache.memory.value(forKey: cacheKey, as: Profile.self) {
            return cached
        }

        return try await ProfileRequestFlight.shared.profile(id: id) { [supabase, cache] in
            if let cached = cache.memory.value(forKey: cacheKey, as: Profile.self) {
                return cached
            }
            let dto: ProfileDTO.Profile = try await supabase.database.selectOne(
                ProfileDTO.Profile.self,
                from: "profiles",
                query: [
                    SupabaseQuery.select(Self.publicProfileSelect),
                    SupabaseQuery.eq("id", id.rawValue),
                ]
            )
            let profile = try ProfileMapper.mapToDomain(dto)
            cache.memory.set(profile, forKey: cacheKey)
            return profile
        }
    }

    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        let unique = Array(Set(ids.map(\.rawValue))).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return [] }

        var cached: [Profile] = []
        var missing: [String] = []
        for id in unique {
            let key = "profile:\(id)"
            if let hit = cache.memory.value(forKey: key, as: Profile.self) {
                cached.append(hit)
            } else {
                missing.append(id)
            }
        }
        guard !missing.isEmpty else { return cached }

        var fetched: [Profile] = []
        for chunk in missing.chunked(into: 80) {
            let rows: [ProfileDTO.Profile] = try await supabase.database.select(
                ProfileDTO.Profile.self,
                from: "profiles",
                query: [
                    SupabaseQuery.select(Self.publicProfileSelect),
                    SupabaseQuery.isIn("id", chunk),
                ]
            )
            for dto in rows {
                guard let profile = try? ProfileMapper.mapToDomain(dto) else { continue }
                cache.memory.set(profile, forKey: "profile:\(profile.id.rawValue)")
                fetched.append(profile)
            }
        }
        return cached + fetched
    }

    func profile(username: String) async throws -> Profile {
        let dto: ProfileDTO.Profile = try await supabase.database.selectOne(
            ProfileDTO.Profile.self,
            from: "profiles",
            query: [
                SupabaseQuery.select(Self.publicProfileSelect),
                SupabaseQuery.eq("username", username),
            ]
        )
        let profile = try ProfileMapper.mapToDomain(dto)
        cache.memory.set(profile, forKey: "profile:\(profile.id.rawValue)")
        return profile
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        let body = ProfileDTO.UpdateBody(
            username: profile.username,
            name: profile.displayName,
            bio: profile.bio,
            avatar_url: profile.avatar?.id,
            trader_type: profile.traderType?.rawValue,
            trading_style: profile.tradingStyle,
            primary_market: profile.primaryMarket,
            is_private: profile.isPrivate
        )
        let dto: ProfileDTO.Profile = try await supabase.database.update(
            body,
            table: "profiles",
            query: [SupabaseQuery.eq("id", profile.id.rawValue)],
            returning: ProfileDTO.Profile.self
        )
        let updated = try ProfileMapper.mapToDomain(dto)
        cache.memory.set(updated, forKey: "profile:\(updated.id.rawValue)")
        cache.memory.remove(forKey: "profile-stats:\(updated.id.rawValue)")
        return updated
    }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        let cacheKey = "profile-stats:\(profileID.rawValue)"
        if let cached = cache.memory.value(forKey: cacheKey, as: ProfileStats.self) {
            return cached
        }

        return try await ProfileRequestFlight.shared.stats(for: profileID) { [self] in
            if let cached = cache.memory.value(forKey: cacheKey, as: ProfileStats.self) {
                return cached
            }

            // Mirror web Profile: followers + posts + summary trades + payout achievement total.
            // Payouts = web `sumPayoutAchievementTotals` over visible public achievements.
            async let followersTask = followerCount(of: profileID)
            async let followingTask = followingCount(of: profileID)
            async let postsTask = profilePostCount(of: profileID)
            async let summaryTask = fetchSummaryTrades(for: profileID)
            async let payoutTask = fetchPayoutTotal(for: profileID)

            let (followers, following, posts, summary, payoutTotal) = try await (
                followersTask,
                followingTask,
                postsTask,
                summaryTask,
                payoutTask
            )

            let overview = ProfileOverviewMetrics.compute(
                from: summary.map {
                    ProfileOverviewMetrics.TradeInput(
                        pnl: DecimalParser.parseFlexible($0.pnl),
                        rr: DecimalParser.parseFlexible($0.rr),
                        mode: $0.mode,
                        accountType: $0.account_type
                    )
                }
            )

            let stats = ProfileStats(
                profileID: profileID,
                followerCount: followers,
                followingCount: following,
                postCount: posts,
                tradeCount: overview.publicTradeCount,
                publicTradeCount: overview.publicTradeCount,
                winRate: overview.winRate,
                profitFactor: overview.profitFactor,
                netPnL: overview.netPnL,
                averageRR: overview.averageRR,
                payoutTotal: payoutTotal,
                expectancy: overview.expectancy
            )
            cache.memory.set(stats, forKey: cacheKey)
            return stats
        }
    }

    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        // Web Profile: select * / user_id / created_at desc — full list (no range).
        let limit = max(page.limit, 500)
        let cursor = page.cursor ?? "-"
        let key = "profiles.wallPosts:\(profileID.rawValue):limit=\(limit):cursor=\(cursor)"
        return try await RepositoryRequestFlight.shared.coalesce(
            key: key,
            resource: "profiles.wallPosts"
        ) { [supabase] in
            var query: [URLQueryItem] = [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
            if let pageCursor = page.cursor, !pageCursor.isEmpty {
                query.append(URLQueryItem(name: "created_at", value: "lt.\(pageCursor)"))
            }
            let rows: [FeedDTO.ProfileWallPost] = try await supabase.database.select(
                FeedDTO.ProfileWallPost.self,
                from: "profile_posts",
                query: query
            )
            let items = rows.compactMap(Self.mapWallPost)
            // Web client re-sort: pinned first, then created_at desc.
            let sorted = items.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return lhs.createdAt > rhs.createdAt
            }
            return CursorPage(
                items: sorted,
                nextCursor: SupabaseQuery.nextCursor(items: rows, limit: limit) { $0.created_at }
            )
        }
    }

    func wallPost(id: PostID) async throws -> Post {
        let dto: FeedDTO.ProfileWallPost = try await supabase.database.selectOne(
            FeedDTO.ProfileWallPost.self,
            from: "profile_posts",
            query: [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("id", id.rawValue),
            ]
        )
        guard let mapped = Self.mapWallPost(dto) else {
            throw AppError.domain(.notFound(entity: "post", id: id.rawValue))
        }
        return mapped
    }

    func createWallPost(authorID: ProfileID, content: String, imageURL: String?) async throws -> Post {
        struct Body: Encodable {
            var user_id: String
            var content: String
            var image_url: String?
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Body(
            user_id: authorID.rawValue,
            content: trimmed,
            image_url: imageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let dto: FeedDTO.ProfileWallPost = try await supabase.database.insert(
            body,
            into: "profile_posts",
            returning: FeedDTO.ProfileWallPost.self
        )
        guard let mapped = Self.mapWallPost(dto) else {
            throw AppError.unknown(message: "Created post but response was incomplete.")
        }
        return mapped
    }

    func deleteWallPost(id: PostID) async throws {
        try await supabase.database.delete(
            from: "profile_posts",
            query: [SupabaseQuery.eq("id", id.rawValue)]
        )
    }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState {
        struct Row: Codable, Sendable { var follower_id: String?; var following_id: String? }
        let key = "profiles.followState:\(viewer.rawValue)->\(target.rawValue)"
        return try await RepositoryRequestFlight.shared.coalesce(
            key: key,
            resource: "profiles.followState"
        ) { [supabase] in
            let rows: [Row] = try await supabase.database.select(
                Row.self,
                from: "followers",
                query: [
                    SupabaseQuery.select("follower_id,following_id"),
                    SupabaseQuery.eq("follower_id", viewer.rawValue),
                    SupabaseQuery.eq("following_id", target.rawValue),
                    URLQueryItem(name: "limit", value: "1"),
                ]
            )
            return rows.isEmpty ? .none : .following
        }
    }

    func follow(from viewer: ProfileID, to target: ProfileID) async throws {
        struct Body: Encodable, Decodable {
            var follower_id: String
            var following_id: String
        }
        _ = try await supabase.database.insert(
            Body(follower_id: viewer.rawValue, following_id: target.rawValue),
            into: "followers",
            returning: Body.self
        )
        cache.memory.remove(forKey: "profile-stats:\(viewer.rawValue)")
        cache.memory.remove(forKey: "profile-stats:\(target.rawValue)")
        RepositoryRequestFlight.shared.invalidate(
            prefix: "profiles.followState:\(viewer.rawValue)->\(target.rawValue)"
        )
    }

    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {
        try await supabase.database.delete(
            from: "followers",
            query: [
                SupabaseQuery.eq("follower_id", viewer.rawValue),
                SupabaseQuery.eq("following_id", target.rawValue),
            ]
        )
        cache.memory.remove(forKey: "profile-stats:\(viewer.rawValue)")
        cache.memory.remove(forKey: "profile-stats:\(target.rawValue)")
        RepositoryRequestFlight.shared.invalidate(
            prefix: "profiles.followState:\(viewer.rawValue)->\(target.rawValue)"
        )
    }

    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        try await relatedProfiles(
            table: "followers",
            foreignKey: "following_id",
            profileKey: "follower_id",
            profileID: profileID,
            page: page
        )
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        try await relatedProfiles(
            table: "followers",
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

    // MARK: - Private (web-parity sources)

    /// Web `sumPayoutAchievementTotals` over `fetchVisibleProfileAchievements` rows.
    private func fetchPayoutTotal(for profileID: ProfileID) async throws -> Decimal {
        struct Row: Codable, Sendable {
            var achievement_type: String?
            var value_numeric: FlexibleNumber?
        }
        let rows: [Row] = try await supabase.database.select(
            Row.self,
            from: "achievements",
            query: [
                SupabaseQuery.select("achievement_type,value_numeric"),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                SupabaseQuery.eq("is_public", "true"),
            ]
        )
        return rows.reduce(Decimal(0)) { partial, row in
            guard Self.isPayoutAchievementType(row.achievement_type) else { return partial }
            return partial + (DecimalParser.parseFlexible(row.value_numeric) ?? 0)
        }
    }

    /// Web `isPayoutAchievementType`.
    private static func isPayoutAchievementType(_ raw: String?) -> Bool {
        let type = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type == "prop_firm_payout"
            || type == "live_trading_payout"
            || type == "payout"
    }

    /// Web: `.from("followers").select("*", { count: "exact", head: true }).eq("following_id", id)`
    private func followerCount(of profileID: ProfileID) async throws -> Int {
        try await supabase.database.count(
            from: "followers",
            query: [SupabaseQuery.eq("following_id", profileID.rawValue)]
        )
    }

    /// Web: `.eq("follower_id", id)` head count.
    private func followingCount(of profileID: ProfileID) async throws -> Int {
        try await supabase.database.count(
            from: "followers",
            query: [SupabaseQuery.eq("follower_id", profileID.rawValue)]
        )
    }

    /// Web wall length from `profile_posts`.
    private func profilePostCount(of profileID: ProfileID) async throws -> Int {
        try await supabase.database.count(
            from: "profile_posts",
            query: [SupabaseQuery.eq("user_id", profileID.rawValue)]
        )
    }

    /// Web `fetchSummaryTrades` — public trades, summary columns only.
    private func fetchSummaryTrades(for profileID: ProfileID) async throws -> [TradeDTO.SummaryTrade] {
        try await supabase.database.select(
            TradeDTO.SummaryTrade.self,
            from: "trades",
            query: [
                SupabaseQuery.select(TradeDTO.profileSummarySelect),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                SupabaseQuery.eq("is_public", "true"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
    }

    /// Web `fetchFollowListPage` — edge IDs then `profiles` by `in.(…)`.
    private func relatedProfiles(
        table: String,
        foreignKey: String,
        profileKey: String,
        profileID: ProfileID,
        page: PageRequest
    ) async throws -> CursorPage<Profile> {
        struct Edge: Codable {
            var follower_id: String?
            var following_id: String?
            var created_at: String?
        }

        let edges: [Edge] = try await supabase.database.select(
            Edge.self,
            from: table,
            query: SupabaseQuery.page(page) + [
                SupabaseQuery.select("\(profileKey),created_at"),
                SupabaseQuery.eq(foreignKey, profileID.rawValue),
            ]
        )

        var seen = Set<String>()
        var orderedIDs: [String] = []
        for edge in edges {
            let raw: String?
            switch profileKey {
            case "follower_id": raw = edge.follower_id
            case "following_id": raw = edge.following_id
            default: raw = nil
            }
            guard let id = raw, !id.isEmpty, seen.insert(id).inserted else { continue }
            orderedIDs.append(id)
        }

        guard !orderedIDs.isEmpty else {
            return CursorPage(items: [], nextCursor: nil)
        }

        let rows: [ProfileDTO.Profile] = try await supabase.database.select(
            ProfileDTO.Profile.self,
            from: "profiles",
            query: [
                SupabaseQuery.select(Self.publicProfileSelect),
                SupabaseQuery.isIn("id", orderedIDs),
            ]
        )

        var byID: [String: Profile] = [:]
        for dto in rows {
            guard let mapped = try? ProfileMapper.mapToDomain(dto) else { continue }
            byID[mapped.id.rawValue] = mapped
        }

        let items = orderedIDs.compactMap { byID[$0] }
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: edges, limit: page.limit) { $0.created_at }
        )
    }

    private static func mapWallPost(_ dto: FeedDTO.ProfileWallPost) -> Post? {
        guard let id = dto.id, let author = dto.user_id else {
            AppLog.networking.error("Skipping profile_posts row — missing id/user_id")
            return nil
        }
        let created = ISO8601.date(from: dto.created_at) ?? Date()
        let media: [MediaReference] = {
            guard let url = dto.image_url?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else { return [] }
            return [MediaReference(id: url, kind: .image, altText: nil)]
        }()
        return Post(
            id: PostID(id),
            authorProfileID: ProfileID(author),
            body: dto.content ?? "",
            media: media,
            visibility: .public,
            linkedTradeID: nil,
            isPinned: dto.is_pinned ?? false,
            createdAt: created,
            updatedAt: created
        )
    }
}
