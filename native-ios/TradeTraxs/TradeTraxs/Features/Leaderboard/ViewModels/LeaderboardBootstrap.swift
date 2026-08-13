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
            let page = LeaderboardTradeWindowFilter.entries(
                from: trades,
                window: context.timeframe.repositoryWindow,
                interval: context.timeframe.customInterval,
                page: PageRequest(cursor: context.cursor, limit: context.limit)
            )
            let profiles = LeaderboardFixtures.profiles(from: page.items)
            for profile in profiles.values { context.detailCache.seed(profile) }
            return Result(
                trades: trades,
                entries: page.items,
                profiles: profiles,
                verified: Set(profiles.values.filter(\.isCreator).map(\.id)),
                followers: LeaderboardFixtures.followerCounts(from: page.items),
                following: Set(page.items.dropFirst(min(3, page.items.count)).prefix(2).map(\.profileID)),
                friends: Set(page.items.dropFirst(min(1, page.items.count)).prefix(2).map(\.profileID)),
                viewerID: viewer,
                nextCursor: page.nextCursor,
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

        let page = LeaderboardTradeWindowFilter.entries(
            from: trades,
            window: context.timeframe.repositoryWindow,
            interval: context.timeframe.customInterval,
            page: PageRequest(cursor: context.cursor, limit: context.limit)
        )

        async let followingTask = loadFollowingIDs(viewer: viewer, context: context)
        let following = await followingTask
        let friends = didFetch
            ? await loadFriendIDs(viewer: viewer, following: following, context: context)
            : []

        let ids = page.items.map(\.profileID)
        async let profilesTask = loadProfiles(ids: ids, context: context)
        async let countsTask = loadFollowerCounts(ids: ids, context: context)
        async let verifiedTask = loadVerified(ids: ids, context: context)

        let profiles = await profilesTask
        let followers = await countsTask
        let verified = await verifiedTask

        for profile in profiles.values {
            context.detailCache.seed(profile)
        }
        if didFetch {
            context.detailCache.seedViewerFollowingIDs(following)
        }

        return Result(
            trades: trades,
            entries: page.items,
            profiles: profiles,
            verified: verified,
            followers: followers,
            following: following,
            friends: friends,
            viewerID: viewer,
            nextCursor: page.nextCursor,
            usedDevelopmentFixtures: false,
            didFetchTrades: didFetch
        )
    }

    // MARK: - Helpers

    private static func loadProfiles(
        ids: [ProfileID],
        context: Context
    ) async -> [ProfileID: Profile] {
        guard !ids.isEmpty else { return [:] }
        if let batch = try? await context.profiles.profiles(ids: ids) {
            return Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })
        }
        return [:]
    }

    private static func loadFollowerCounts(
        ids: [ProfileID],
        context: Context
    ) async -> [ProfileID: Int] {
        guard !ids.isEmpty else { return [:] }
        let counts = (try? await context.explore.socialCounts(for: ids)) ?? .empty
        return counts.followers
    }

    private static func loadVerified(
        ids: [ProfileID],
        context: Context
    ) async -> Set<ProfileID> {
        guard !ids.isEmpty else { return [] }
        var verified = Set<ProfileID>()
        await withTaskGroup(of: ProfileID?.self) { group in
            for id in ids.prefix(40) {
                group.addTask {
                    if let creator = try? await context.profiles.creator(for: id), creator.isVerified {
                        return id
                    }
                    return nil
                }
            }
            for await id in group {
                if let id { verified.insert(id) }
            }
        }
        return verified
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
            let page = try await context.profiles.followers(
                of: viewer,
                page: PageRequest(limit: 500)
            )
            return Set(page.items.map(\.id)).intersection(following)
        } catch {
            return []
        }
    }
}
