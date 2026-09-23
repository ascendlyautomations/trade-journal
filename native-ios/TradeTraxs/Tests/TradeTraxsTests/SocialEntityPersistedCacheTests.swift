import XCTest
@testable import TradeTraxs

@MainActor
final class SocialEntityPersistedCacheTests: XCTestCase {
    private let viewerA = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let viewerB = ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

    override func setUp() {
        super.setUp()
        SocialEntityPersistedCacheTestHooks.forceSynchronousDiskWrites = true
        SocialEntityWriteGeneration.resetForTesting()
        SocialEntityPersistedCacheCoordinator.clearAll()
    }

    override func tearDown() {
        SocialEntityPersistedCacheCoordinator.flushPendingDiskWritesForTesting()
        SocialEntityPersistedCacheTestHooks.forceSynchronousDiskWrites = false
        SocialEntityPersistedCacheCoordinator.clearAll()
        SocialEntityWriteGeneration.resetForTesting()
        super.tearDown()
    }

    func testFeedEntityAvailableForShareResolution() {
        let post = makePost(id: "post-share", body: "Hello from feed")
        SocialEntityPersistedCacheCoordinator.savePost(
            post,
            viewerID: viewerA,
            source: .feed,
            mergeMode: .replace
        )
        let loaded = SocialEntityPersistedCacheCoordinator.loadPost(
            id: PostID("post-share"),
            viewerID: viewerA,
            purpose: "test"
        )
        XCTAssertEqual(loaded?.body, "Hello from feed")
    }

    func testPartialPostMergePreservesRicherBody() {
        let rich = makePost(id: "post-merge", body: "Full body text")
        SocialEntityPersistedCacheCoordinator.savePost(
            rich,
            viewerID: viewerA,
            source: .profile,
            mergeMode: .replace
        )
        var partial = rich
        partial.body = ""
        partial.updatedAt = rich.updatedAt.addingTimeInterval(-10)
        SocialEntityPersistedCacheCoordinator.savePost(
            partial,
            viewerID: viewerA,
            source: .mutation,
            mergeMode: .merge
        )
        let loaded = SocialEntityPersistedCacheCoordinator.loadPost(
            id: PostID("post-merge"),
            viewerID: viewerA,
            purpose: "test"
        )
        XCTAssertEqual(loaded?.body, "Full body text")
    }

    func testTradeSummaryNeverStoresAuthoritativeDetailFields() {
        let summary = makeTradeSummary(id: "trade-boundary")
        SocialEntityPersistedCacheCoordinator.saveTradeSummary(
            summary,
            viewerID: viewerA,
            source: .feed,
            mergeMode: .replace
        )
        let preview = SocialEntityDiskCache.loadTrade(id: TradeID("trade-boundary"), viewerID: viewerA)
        XCTAssertNotNil(preview)
        XCTAssertNil(preview?.psychologyNotes)
    }

    func testDeleteRemovesEntity() {
        SocialEntityPersistedCacheCoordinator.savePost(
            makePost(id: "gone", body: "x"),
            viewerID: viewerA,
            source: .feed,
            mergeMode: .replace
        )
        SocialEntityPersistedCacheCoordinator.removePost(id: PostID("gone"), viewerID: viewerA)
        SocialEntityPersistedCacheCoordinator.flushPendingDiskWritesForTesting()
        XCTAssertNil(
            SocialEntityPersistedCacheCoordinator.loadPost(
                id: PostID("gone"),
                viewerID: viewerA,
                purpose: "test"
            )
        )
    }

    func testViewerIsolation() {
        SocialEntityPersistedCacheCoordinator.savePost(
            makePost(id: "secret", body: "private"),
            viewerID: viewerA,
            source: .profile,
            mergeMode: .replace
        )
        XCTAssertNil(
            SocialEntityPersistedCacheCoordinator.loadPost(
                id: PostID("secret"),
                viewerID: viewerB,
                purpose: "test"
            )
        )
    }

    func testNewerGenerationWinsOverStaleAsyncSave() {
        let postA = makePost(id: "race", body: "first")
        SocialEntityPersistedCacheCoordinator.savePost(
            postA,
            viewerID: viewerA,
            source: .feed,
            mergeMode: .replace
        )
        var postB = postA
        postB.body = "second"
        SocialEntityPersistedCacheCoordinator.savePost(
            postB,
            viewerID: viewerA,
            source: .feed,
            mergeMode: .replace
        )
        SocialEntityPersistedCacheCoordinator.flushPendingDiskWritesForTesting()
        let loaded = SocialEntityPersistedCacheCoordinator.loadPost(
            id: PostID("race"),
            viewerID: viewerA,
            purpose: "test"
        )
        XCTAssertEqual(loaded?.body, "second")
    }

    func testPrivateTradeVisibilityRemovesEntity() {
        let trade = makePublicTrade(id: "priv-trade")
        SocialEntityPersistedCacheCoordinator.saveTradeSummary(
            TradeSummaryMapper.summary(fromPartialListTrade: trade),
            viewerID: viewerA,
            source: .feed,
            mergeMode: .replace
        )
        var privateTrade = trade
        privateTrade.visibility = .private
        FeedPersistedCacheCoordinator.patchTrade(privateTrade, viewerID: viewerA)
        SocialEntityPersistedCacheCoordinator.flushPendingDiskWritesForTesting()
        XCTAssertNil(
            SocialEntityPersistedCacheCoordinator.loadTradeSummary(
                id: TradeID("priv-trade"),
                viewerID: viewerA,
                purpose: "test"
            )
        )
    }

    // MARK: - Fixtures

    private func makePost(id: String, body: String) -> Post {
        Post(
            id: PostID(id),
            authorProfileID: viewerA,
            body: body,
            media: [],
            visibility: .public,
            linkedTradeID: nil,
            isPinned: false,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func makeTradeSummary(id: String) -> TradeSummary {
        TradeSummary(
            id: TradeID(id),
            ownerProfileID: viewerA,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            realizedPnL: Money(amount: 1, currencyCode: "USD"),
            riskReward: 1,
            points: 1,
            quantity: 1,
            entryAt: .now,
            exitAt: .now,
            createdAt: .now,
            visibility: .public,
            publicCaption: nil,
            notePreview: nil,
            thumbnail: nil,
            imageDisplayMode: .fit,
            mode: .live,
            publicAccountBadge: nil,
            durationSeconds: nil,
            durationText: nil
        )
    }

    private func makePublicTrade(id: String) -> Trade {
        TradeSummaryMapper.previewTrade(from: makeTradeSummary(id: id))
    }
}
