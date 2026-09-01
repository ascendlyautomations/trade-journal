import XCTest
@testable import TradeTraxs

@MainActor
final class FeedRpcProjectionN3Tests: XCTestCase {
    override func tearDown() {
        FeedRpcLoadProbe.resetForTesting()
        FeedSessionStore.shared.invalidate()
        super.tearDown()
    }

    func testTradeItemPayloadSeedsTradeWithoutNetwork() throws {
        let bootstrap: FeedBootstrapV1 = try decode(FeedRpcProjectionFixtures.followingAllMixed)
        let cache = DetailPresentationCache()
        let seed = FeedRpcProjectionSeeder.seed(bootstrap: bootstrap, detailCache: cache)

        XCTAssertGreaterThanOrEqual(seed.trades, 1)
        XCTAssertGreaterThanOrEqual(seed.posts, 1)
        XCTAssertNotNil(cache.trade(id: TradeID("dddddddd-dddd-dddd-dddd-dddddddddddd")))

        let applied = FeedBootstrapApplier.apply(bootstrap)
        let entries = FeedBootstrap.buildEntriesFromSeededItems(applied.items, detailCache: cache)
        XCTAssertEqual(entries.count, applied.items.count)
        XCTAssertFalse(entries.isEmpty)
    }

    func testAchievementPayloadSeedsFromNestedObject() throws {
        let bootstrap: FeedBootstrapV1 = try decode(FeedRpcProjectionFixtures.followingAllMixed)
        let cache = DetailPresentationCache()
        _ = FeedRpcProjectionSeeder.seed(bootstrap: bootstrap, detailCache: cache)
        XCTAssertNotNil(cache.achievement(id: AchievementID("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")))
    }

    func testReelUsesThumbnailNotVideoFetch() throws {
        let bootstrap: FeedBootstrapV1 = try decode(FeedRpcProjectionFixtures.followingAllMixed)
        let cache = DetailPresentationCache()
        _ = FeedRpcProjectionSeeder.seed(bootstrap: bootstrap, detailCache: cache)
        let reel = cache.reel(id: ReelID("reel-1"))
        XCTAssertNotNil(reel)
        XCTAssertEqual(reel?.thumbnail?.kind, .image)
    }

    func testBuildEntriesSkipsMissingCacheWithoutSilentEmptySuccess() throws {
        let bootstrap: FeedBootstrapV1 = try decode(FeedRpcProjectionFixtures.followingAllMixed)
        let applied = FeedBootstrapApplier.apply(bootstrap)
        let entries = FeedBootstrap.buildEntriesFromSeededItems(
            applied.items,
            detailCache: DetailPresentationCache()
        )
        XCTAssertTrue(entries.isEmpty)
    }

    func testSuccessfulSeedDoesNotRecordNetworkHydrate() throws {
        let bootstrap: FeedBootstrapV1 = try decode(FeedRpcProjectionFixtures.followingAllMixed)
        let cache = DetailPresentationCache()
        _ = FeedRpcProjectionSeeder.seed(bootstrap: bootstrap, detailCache: cache)
        let applied = FeedBootstrapApplier.apply(bootstrap)
        let entries = FeedBootstrap.buildEntriesFromSeededItems(applied.items, detailCache: cache)
        XCTAssertEqual(entries.count, applied.items.count)
        XCTAssertFalse(FeedRpcLoadProbe.usedNetworkHydrate)
    }

    func testFeedInteractionTargetsUseFeedRowIDs() throws {
        let bootstrap: FeedBootstrapV1 = try decode(FeedRpcProjectionFixtures.followingAllMixed)
        let cache = DetailPresentationCache()
        _ = FeedRpcProjectionSeeder.seed(bootstrap: bootstrap, detailCache: cache)
        let applied = FeedBootstrapApplier.apply(bootstrap)
        let entries = FeedBootstrap.buildEntriesFromSeededItems(applied.items, detailCache: cache)

        let tradeEntry = try XCTUnwrap(entries.first { if case .trade = $0 { return true }; return false })
        XCTAssertEqual(tradeEntry.interactionTarget, .feedPost(PostID("post-1")))
        XCTAssertEqual(tradeEntry.feedTradeEngagementPostID, PostID("post-1"))

        let postEntry = try XCTUnwrap(entries.first { if case .post = $0 { return true }; return false })
        XCTAssertEqual(postEntry.interactionTarget, .profilePost(PostID("pp-1")))

        let reelEntry = try XCTUnwrap(entries.first { if case .clip = $0 { return true }; return false })
        XCTAssertEqual(reelEntry.interactionTarget, .reel(ReelID("reel-1")))

        let achievementEntry = try XCTUnwrap(entries.first { if case .achievement = $0 { return true }; return false })
        XCTAssertEqual(achievementEntry.interactionTarget, .achievement(AchievementID("ap-1")))
        XCTAssertEqual(achievementEntry.feedAchievementPostID, AchievementID("ap-1"))

        XCTAssertNotNil(applied.engagementByTarget[.feedPost(PostID("post-1"))])
        XCTAssertNotNil(applied.engagementByTarget[.profilePost(PostID("pp-1"))])
        XCTAssertNil(applied.engagementByTarget[.trade(TradeID("dddddddd-dddd-dddd-dddd-dddddddddddd"))])

        for entry in entries {
            if let snapshot = applied.engagementByTarget[entry.interactionTarget] {
                XCTAssertGreaterThanOrEqual(snapshot.likeCount, 0)
            }
        }
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

enum FeedRpcProjectionFixtures {
    /// Mirrors web `feedContractFixtures` mixed page shape.
    static let followingAllMixed = """
    {"meta":{"contract_version":"v1","server_time":"2026-08-20T12:00:00.000Z","viewer_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"},"data":{"scope":"following","content_filter":"all","items":[{"kind":"post","id":"post-1","created_at":"2026-08-20T12:00:00.000Z","author_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","payload":{"id":"post-1","user_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","trade_id":"dddddddd-dddd-dddd-dddd-dddddddddddd","created_at":"2026-08-20T12:00:00.000Z","pnl":120,"rr":2.5,"image_url":"https://cdn.example/trade.png","profiles":{"username":"trader_a","avatar_url":"https://cdn.example/a.jpg"},"trades":{"ticker":"ES","direction":"long","public_description":"Breakout","entry_time":"2026-08-20T11:00:00.000Z","is_public":true}}},{"kind":"profile_post","id":"pp-1","created_at":"2026-08-20T11:30:00.000Z","author_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","payload":{"id":"pp-1","user_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","content":"Market thoughts","image_url":null,"created_at":"2026-08-20T11:30:00.000Z","profiles":{"username":"trader_b","avatar_url":null}}},{"kind":"reel","id":"reel-1","created_at":"2026-08-20T11:00:00.000Z","author_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","payload":{"id":"reel-1","user_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","caption":"Clip","video_url":"https://cdn.example/v.mp4","thumbnail_url":"https://cdn.example/t.jpg","duration_seconds":12,"visibility":"public","trade_id":null,"created_at":"2026-08-20T11:00:00.000Z","profiles":{"username":"trader_a","avatar_url":null}}},{"kind":"achievement_post","id":"ap-1","created_at":"2026-08-20T10:00:00.000Z","author_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","payload":{"id":"ap-1","user_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","achievement_id":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee","created_at":"2026-08-20T10:00:00.000Z","achievements":{"id":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee","title":"Win streak","image_url":"https://cdn.example/badge.png","is_public":true},"profiles":{"username":"trader_b","avatar_url":null}}}],"authors":{"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb":{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","username":"trader_a","display_name":"Trader A","avatar_url":null},"cccccccc-cccc-cccc-cccc-cccccccccccc":{"id":"cccccccc-cccc-cccc-cccc-cccccccccccc","username":"trader_b","display_name":"Trader B","avatar_url":null}},"engagement":{"post-1":{"like_count":3,"comment_count":1,"liked_by_viewer":false},"pp-1":{"like_count":1,"comment_count":0,"liked_by_viewer":true}},"stories":[],"story_authors":{},"next_cursor":null,"page_meta":{"limit":8,"returned":4,"has_more":false},"following_ids_echo":["bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"]}}
    """
}
