import Foundation

/// Coordinated Leaderboard first-paint — owned exclusively by ``LeaderboardScreenViewModel``.
///
/// Loads the shared public trade set once (web `/api/leaderboard/trades`), then ranks
/// client-side for the selected window. Child views never call repositories.
@MainActor
enum LeaderboardBootstrap: ScreenBootstrap {
    struct Context {
        var leaderboard: any LeaderboardRepository
        var profiles: any ProfileRepository
        var explore: any ExploreRepository
        var session: any SessionProviding
        var detailCache: DetailPresentationCache
        var audience: LeaderboardAudience
        var timeframe: LeaderboardTimeframe
        var category: LeaderboardCategory
        var cursor: String?
        var limit: Int = 100
        var forceNetwork: Bool = false
        /// When set, skip network and re-rank from these trades (timeframe change).
        var cachedTrades: [LeaderboardTradeRow]? = nil
    }

    struct Result {
        var trades: [LeaderboardTradeRow]
        var entries: [LeaderboardEntry]
        var profiles: [ProfileID: Profile]
        var verified: Set<ProfileID>
        var followers: [ProfileID: Int]
        var following: Set<ProfileID>
        var friends: Set<ProfileID>
        var viewerID: ProfileID?
        var nextCursor: String?
        var timeframeResolution: LeaderboardTimeframeFallback.Resolution
        var usedDevelopmentFixtures: Bool
        var didFetchTrades: Bool
    }

    static func load(_ context: Context) async throws -> Result {
        try await loadPage(context)
    }

    static func loadPage(_ context: Context) async throws -> Result {
        let viewer = await context.session.currentUserID.map { ProfileID($0.rawValue) }

        if let viewer, ProfileSectionSupport.isLocalDevelopmentProfile(viewer) {
            let trades = LeaderboardFixtures.trades(viewerID: viewer)
            let resolved = LeaderboardTimeframeFallback.resolveWindow(
                trades: trades,
                requested: context.timeframe,
                limit: context.limit
            )
            let profiles = LeaderboardFixtures.profiles(from: resolved.entries)
            for profile in profiles.values { context.detailCache.seed(profile) }
            return Result(
                trades: trades,
                entries: resolved.entries,
                profiles: profiles,
                verified: Set(profiles.values.filter(\.isCreator).map(\.id)),
                followers: LeaderboardFixtures.followerCounts(from: resolved.entries),
                following: Set(resolved.entries.dropFirst(min(3, resolved.entries.count)).prefix(2).map(\.profileID)),
                friends: Set(resolved.entries.dropFirst(min(1, resolved.entries.count)).prefix(2).map(\.profileID)),
                viewerID: viewer,
                nextCursor: resolved.nextCursor,
                timeframeResolution: resolved.resolution,
                usedDevelopmentFixtures: true,
                didFetchTrades: true
            )
        }

        let trades: [LeaderboardTradeRow]
        let didFetch: Bool
        if let cached = context.cachedTrades {
            trades = cached
            didFetch = false
        } else {
            trades = try await context.leaderboard.tradeRows(forceNetwork: context.forceNetwork)
            didFetch = true
        }

        let resolved = LeaderboardTimeframeFallback.resolveWindow(
            trades: trades,
            requested: context.timeframe,
            limit: context.limit
        )
        let ids = resolved.entries.map(\.profileID)

        async let followingTask = loadFollowingIDs(viewer: viewer, context: context)

        let following = await followingTask

        let friends: Set<ProfileID>
        if context.audience == .friends, didFetch {
            friends = await loadFriendIDs(viewer: viewer, following: following, context: context)
        } else {
            friends = []
        }

        async let countsTask = loadFollowerCounts(ids: ids, context: context)
        let profiles = await loadProfiles(ids: ids, trades: trades, context: context)
        let followers = await countsTask

        if didFetch {
            context.detailCache.seedViewerFollowingIDs(following)
        }

        return Result(
            trades: trades,
            entries: resolved.entries,
            profiles: profiles,
            verified: [],
            followers: followers,
            following: following,
            friends: friends,
            viewerID: viewer,
            nextCursor: resolved.nextCursor,
            timeframeResolution: resolved.resolution,
            usedDevelopmentFixtures: false,
            didFetchTrades: didFetch
        )
    }

    /// Friends filter only — one followers edge query intersected with cached following IDs.
    static func loadFriends(
        viewer: ProfileID,
        following: Set<ProfileID>,
        context: Context
    ) async -> Set<ProfileID> {
        await loadFriendIDs(viewer: viewer, following: following, context: context)
    }

    // MARK: - Helpers

    /// Batch-hydrate missing profiles for visible leaderboard traders.
    /// Merges ``existing``, detail-cache hits, embedded trade identity, then one ``profiles.batch``.
    static func hydrateMissingProfiles(
        ids: [ProfileID],
        trades: [LeaderboardTradeRow],
        existing: [ProfileID: Profile],
        context: Context
    ) async -> [ProfileID: Profile] {
        guard !ids.isEmpty else { return existing }

        var profiles = existing
        let embedded = LeaderboardTradeIdentity.profiles(from: trades)
        for (profileID, embeddedProfile) in embedded where ids.contains(profileID) {
            profiles[profileID] = LeaderboardTradeIdentity.mergeLeaderboardProfile(
                existing: profiles[profileID],
                fetched: embeddedProfile
            )
        }

        let unique = Array(Set(ids))
        for profileID in unique {
            guard !LeaderboardTradeIdentity.isLeaderboardCacheComplete(profiles[profileID] ?? placeholderProfile(profileID)) else {
                continue
            }
            if let cached = context.detailCache.profile(id: profileID) {
                profiles[profileID] = LeaderboardTradeIdentity.mergeLeaderboardProfile(
                    existing: profiles[profileID],
                    fetched: cached
                )
            }
        }

        #if DEBUG
        ProfileAvatarSourceKind.logLeaderboardStage("embedded", profiles: profiles.values.filter { unique.contains($0.id) })
        #endif

        let remaining = unique.filter { profileID in
            !LeaderboardTradeIdentity.isLeaderboardCacheComplete(
                profiles[profileID] ?? placeholderProfile(profileID)
            )
        }
        guard !remaining.isEmpty else {
            for profileID in unique {
                if let profile = profiles[profileID] {
                    context.detailCache.seed(profile)
                }
            }
            #if DEBUG
            ProfileAvatarSourceKind.logLeaderboardStage(
                "final",
                profiles: unique.compactMap { profiles[$0] }
            )
            #endif
            return profiles
        }

        guard let batch = try? await SessionProfileStore.shared.profiles(
            ids: remaining,
            detailCache: context.detailCache,
            repository: context.profiles,
            forceNetwork: context.forceNetwork,
            acceptCached: LeaderboardTradeIdentity.isLeaderboardCacheComplete
        ) else {
            #if DEBUG
            ProfileAvatarSourceKind.logLeaderboardStage(
                "final",
                profiles: unique.compactMap { profiles[$0] }
            )
            #endif
            return profiles
        }

        #if DEBUG
        ProfileAvatarSourceKind.logLeaderboardStage("batchMapped", profiles: batch)
        #endif

        for fetched in batch {
            let merged = LeaderboardTradeIdentity.mergeLeaderboardProfile(
                existing: profiles[fetched.id],
                fetched: fetched
            )
            profiles[fetched.id] = merged
            context.detailCache.seed(merged)
        }

        #if DEBUG
        ProfileAvatarSourceKind.logLeaderboardStage(
            "final",
            profiles: unique.compactMap { profiles[$0] }
        )
        #endif
        return profiles
    }

    private static func placeholderProfile(_ profileID: ProfileID) -> Profile {
        Profile(
            id: profileID,
            userID: UserID(profileID.rawValue),
            username: "",
            displayName: "",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }

    private static func loadProfiles(
        ids: [ProfileID],
        trades: [LeaderboardTradeRow],
        context: Context
    ) async -> [ProfileID: Profile] {
        await hydrateMissingProfiles(
            ids: ids,
            trades: trades,
            existing: [:],
            context: context
        )
    }

    private static func loadFollowerCounts(
        ids: [ProfileID],
        context: Context
    ) async -> [ProfileID: Int] {
        guard !ids.isEmpty else { return [:] }
        let unique = Array(Set(ids))
        let key = unique.map(\.rawValue).sorted().joined(separator: ",")
        let counts = (try? await RepositoryRequestFlight.shared.coalesce(
            key: "leaderboard.socialCounts:\(key)",
            resource: "explore.socialCounts",
            fetch: { try await context.explore.socialCounts(for: unique) }
        )) ?? .empty
        return counts.followers
    }

    private static func loadFollowingIDs(
        viewer: ProfileID?,
        context: Context
    ) async -> Set<ProfileID> {
        guard let viewer else { return [] }
        if !context.forceNetwork, let cached = context.detailCache.viewerFollowingIDs() {
            return cached
        }
        do {
            let raw = try await SessionFollowingStore.shared.followingIDs(
                viewerID: viewer.rawValue,
                forceNetwork: context.forceNetwork
            ) {
                let page = try await context.profiles.following(
                    of: viewer,
                    page: PageRequest(limit: 500)
                )
                return page.items.map(\.id.rawValue)
            }
            return Set(raw.map { ProfileID($0) })
        } catch {
            return context.detailCache.viewerFollowingIDs() ?? []
        }
    }

    private static func loadFriendIDs(
        viewer: ProfileID?,
        following: Set<ProfileID>,
        context: Context
    ) async -> Set<ProfileID> {
        guard let viewer, !following.isEmpty else { return [] }
        do {
            let page = try await RepositoryRequestFlight.shared.coalesce(
                key: "leaderboard.viewerFollowers:\(viewer.rawValue)",
                resource: "profiles.followers",
                fetch: {
                    try await context.profiles.followers(
                        of: viewer,
                        page: PageRequest(limit: 500)
                    )
                }
            )
            return Set(page.items.map(\.id)).intersection(following)
        } catch {
            return []
        }
    }
}
