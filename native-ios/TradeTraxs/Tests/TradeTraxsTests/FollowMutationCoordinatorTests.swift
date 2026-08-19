import XCTest
@testable import TradeTraxs

@MainActor
final class FollowMutationCoordinatorTests: XCTestCase {
    override func tearDown() {
        FollowMutationCoordinator.shared.invalidate()
        ExploreSessionStore.shared.invalidate()
        LeaderboardSessionStore.shared.invalidate()
        super.tearDown()
    }

    func testFollowPatchesEdgeCountsExploreAndLeaderboard() {
        let cache = DetailPresentationCache()
        let viewer = ProfileID("viewer-1")
        let target = ProfileID("target-1")
        cache.seed(
            stats: ProfileStats(
                profileID: target,
                followerCount: 10,
                followingCount: 3,
                postCount: 1,
                tradeCount: 1,
                publicTradeCount: 1
            )
        )
        cache.seed(
            stats: ProfileStats(
                profileID: viewer,
                followerCount: 2,
                followingCount: 5,
                postCount: 0,
                tradeCount: 0,
                publicTradeCount: 0
            )
        )
        cache.seedViewerFollowingIDs([])

        let profileStore = CurrentUserProfileStore(
            profiles: CompositionRoot.bootstrap().data.profiles,
            session: CompositionRoot.bootstrap().data.session,
            imagePipeline: CompositionRoot.bootstrap().data.imagePipeline,
            detailCache: cache
        )
        // Seed owner stats without network.
        profileStore.applyFollowingCountDelta(0)
        // Manually set via apply deltas after configuring coordinator.
        FollowMutationCoordinator.shared.configure(
            detailCache: cache,
            currentUserProfile: profileStore
        )

        ExploreSessionStore.shared.applyBootstrap(
            traders: [
                ExploreTraderSuggestion(
                    profile: Profile(
                        id: target,
                        userID: UserID(target.rawValue),
                        username: "target",
                        displayName: "Target",
                        bio: nil,
                        avatar: nil,
                        traderType: nil,
                        tradingStyle: nil,
                        primaryMarket: nil,
                        startedTradingAt: nil,
                        isPrivate: false,
                        isCreator: false,
                        createdAt: Date()
                    ),
                    followerCount: 10,
                    score: 1,
                    identityLine: nil
                )
            ],
            rooms: [],
            following: [],
            tradersNextCursor: nil
        )
        LeaderboardSessionStore.shared.applyBootstrap(
            trades: [],
            entries: [],
            profiles: [:],
            verified: [],
            followers: [target: 10],
            following: [],
            friends: [],
            viewerID: viewer,
            nextCursor: nil,
            audience: .all,
            timeframe: .month,
            category: .pnl
        )

        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewer,
            target: target,
            isFollowing: true
        )

        XCTAssertEqual(cache.viewerFollowEdge(for: target), true)
        XCTAssertEqual(cache.stats(for: target)?.followerCount, 11)
        XCTAssertEqual(cache.stats(for: viewer)?.followingCount, 6)
        XCTAssertTrue(ExploreSessionStore.shared.viewerFollowingIDs.contains(target))
        XCTAssertEqual(ExploreSessionStore.shared.suggestedTraders.first?.followerCount, 11)
        XCTAssertTrue(LeaderboardSessionStore.shared.followingIDs.contains(target))
        XCTAssertEqual(LeaderboardSessionStore.shared.followerCounts[target], 11)

        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewer,
            target: target,
            isFollowing: false
        )
        XCTAssertEqual(cache.viewerFollowEdge(for: target), false)
        XCTAssertEqual(cache.stats(for: target)?.followerCount, 10)
        XCTAssertEqual(cache.stats(for: viewer)?.followingCount, 5)
        XCTAssertFalse(ExploreSessionStore.shared.viewerFollowingIDs.contains(target))
    }

    func testIdempotentFollowDoesNotDoubleCount() {
        let cache = DetailPresentationCache()
        let viewer = ProfileID("viewer-2")
        let target = ProfileID("target-2")
        cache.seed(
            stats: ProfileStats(
                profileID: target,
                followerCount: 1,
                followingCount: 0,
                postCount: 0,
                tradeCount: 0,
                publicTradeCount: 0
            )
        )
        FollowMutationCoordinator.shared.configure(
            detailCache: cache,
            currentUserProfile: CurrentUserProfileStore(
                profiles: CompositionRoot.bootstrap().data.profiles,
                session: CompositionRoot.bootstrap().data.session,
                imagePipeline: CompositionRoot.bootstrap().data.imagePipeline,
                detailCache: cache
            )
        )
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewer,
            target: target,
            isFollowing: true
        )
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewer,
            target: target,
            isFollowing: true
        )
        XCTAssertEqual(cache.stats(for: target)?.followerCount, 2)
    }
}
