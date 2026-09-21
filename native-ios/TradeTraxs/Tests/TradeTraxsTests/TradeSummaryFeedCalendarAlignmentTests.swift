import XCTest
@testable import TradeTraxs

@MainActor
final class TradeSummaryFeedCalendarAlignmentTests: XCTestCase {
    override func tearDown() {
        FeedDiskCache.clearAll()
        FeedSessionStore.shared.invalidate()
        super.tearDown()
    }

    func testFeedRpcSeedsPresentationSummaryNotAuthoritativeDetail() throws {
        let bootstrap: FeedBootstrapV1 = try decode(FeedRpcProjectionFixtures.followingAllMixed)
        let cache = DetailPresentationCache()
        _ = FeedRpcProjectionSeeder.seed(bootstrap: bootstrap, detailCache: cache)
        let applied = FeedBootstrapApplier.apply(bootstrap)
        let entries = FeedBootstrap.buildEntriesFromSeededItems(applied.items, detailCache: cache)

        let tradeEntry = try XCTUnwrap(entries.first { if case .trade = $0 { return true }; return false })
        if case .trade(_, let summary) = tradeEntry {
            XCTAssertEqual(summary.symbol.ticker, "ES")
            XCTAssertNil(cache.authoritativeDetail(id: summary.id))
            XCTAssertEqual(cache.tradeAuthority(for: summary.id), .listSeed)
        } else {
            XCTFail("Expected trade entry")
        }
    }

    func testCalendarDayWireMapsToTradeSummaries() throws {
        let json = """
        {"revision":1,"calendar_day":"2026-09-10","aggregate":{"trade_count":1,"win_count":1,"loss_count":0,"breakeven_count":0,"net_pnl":120,"gross_profit":120,"gross_loss":0},"trades":[{"id":"trade-cal-1","user_id":"owner-1","ticker":"NQ","direction":"long","pnl":120,"rr":2,"contracts":1,"entry_time":"2026-09-10T14:30:00.000Z","exit_time":"2026-09-10T15:00:00.000Z","created_at":"2026-09-10T15:05:00.000Z","is_public":true,"public_description":"Open drive","mode":"live","duration_seconds":1800,"duration_text":"30m"}]}
        """
        let bootstrap: AnalyticsCalendarDayTradesBootstrapV1 = try decode(json)
        let owner = ProfileID("owner-1")
        let summaries = TradeSummaryCalendarMapper.mapDayTrades(bootstrap.trades, ownerID: owner)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].id.rawValue, "trade-cal-1")
        XCTAssertEqual(summaries[0].symbol.ticker, "NQ")
        XCTAssertEqual(summaries[0].publicCaption, "Open drive")
    }

    func testFeedDiskCacheSchemaV2RoundTripUsesTradeSummary() throws {
        let owner = ProfileID("owner-1")
        let viewer = ProfileID("viewer-1")
        let trade = ProfileTradeFixtures.samples(owner: owner).first!
        let summary = TradeSummaryMapper.summary(fromPartialListTrade: trade)
        let item = FeedFixtures.feedItem(
            id: "feed-\(trade.id.rawValue)",
            kind: .trade,
            authorProfileID: trade.ownerProfileID,
            createdAt: trade.createdAt,
            tradeID: trade.id,
            caption: trade.publicCaption,
            mediaURL: trade.thumbnail?.id
        )
        let entry: FeedTimelineEntry = .trade(item, summary)
        let blob = FeedDiskCache.PageBlob(
            viewerID: viewer.rawValue,
            scope: FeedScope.following.rawValue,
            contentFilter: FeedContentFilter.all.rpcValue,
            savedAt: Date(),
            lastAccessedAt: Date(),
            entries: [entry],
            stories: [],
            nextCursor: nil
        )
        FeedDiskCache.savePage(blob)
        let loaded = try XCTUnwrap(
            FeedDiskCache.loadPage(viewerID: viewer, scope: .following, contentFilter: .all)
        )
        XCTAssertEqual(loaded.schemaVersion, FeedDiskCache.schemaVersion)
        if case .trade(_, let roundTrip) = loaded.entries[0] {
            XCTAssertEqual(roundTrip.id, summary.id)
        } else {
            XCTFail("Expected trade summary entry")
        }
        FeedDiskCache.clear(viewerID: viewer)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
