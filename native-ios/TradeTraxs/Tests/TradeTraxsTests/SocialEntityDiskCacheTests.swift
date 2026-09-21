import XCTest
@testable import TradeTraxs

final class SocialEntityDiskCacheTests: XCTestCase {
    private let viewer = ProfileID("viewer-social-1")

    override func tearDown() {
        SocialEntityDiskCache.clearAll()
        super.tearDown()
    }

    func testTradeSummaryRoundTrip() {
        let summary = makeSummary(id: "trade-a")
        SocialEntityDiskCache.saveTradeSummary(summary, viewerID: viewer)
        let loaded = SocialEntityDiskCache.loadTradeSummary(id: TradeID("trade-a"), viewerID: viewer)
        XCTAssertEqual(loaded?.symbol.ticker, "ES")
        XCTAssertEqual(loaded?.id, summary.id)
    }

    func testLoadTradeReturnsPreviewNotAuthoritativeDetail() {
        let summary = makeSummary(id: "trade-b")
        SocialEntityDiskCache.saveTradeSummary(summary, viewerID: viewer)
        let preview = SocialEntityDiskCache.loadTrade(id: TradeID("trade-b"), viewerID: viewer)
        XCTAssertNotNil(preview)
        XCTAssertNil(preview?.psychologyNotes)
        XCTAssertNil(preview?.importSource)
    }

    func testViewerIsolation() {
        let other = ProfileID("viewer-social-2")
        SocialEntityDiskCache.saveTradeSummary(makeSummary(id: "trade-c"), viewerID: viewer)
        XCTAssertNil(SocialEntityDiskCache.loadTradeSummary(id: TradeID("trade-c"), viewerID: other))
    }

    func testLegacyTradeBlobMigratesToSummary() throws {
        let trade = TradeSummaryMapper.previewTrade(from: makeSummary(id: "legacy-1"))
        let legacy = SocialEntityDiskCache.Record(
            schemaVersion: 1,
            viewerID: viewer.rawValue,
            kind: .trade,
            entityID: "legacy-1",
            savedAt: Date(),
            lastAccessedAt: Date(),
            tradeSummary: nil,
            trade: trade,
            post: nil,
            reel: nil,
            achievement: nil,
            profile: nil
        )
        let dir = PersistentAppDataDiskCache.directoryURL(component: SocialEntityDiskCache.folderName)
        XCTAssertNotNil(dir)
        let url = dir!.appendingPathComponent("entity-\(viewer.rawValue)-trade-legacy-1.json")
        try JSONEncoder().encode(legacy).write(to: url)
        let migrated = SocialEntityDiskCache.loadTradeSummary(id: TradeID("legacy-1"), viewerID: viewer)
        XCTAssertEqual(migrated?.id.rawValue, "legacy-1")
        let reloaded: SocialEntityDiskCache.Record? = try JSONDecoder().decode(
            SocialEntityDiskCache.Record.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(reloaded?.schemaVersion, SocialEntityDiskCache.schemaVersion)
        XCTAssertNotNil(reloaded?.tradeSummary)
        XCTAssertNil(reloaded?.trade)
    }

    private func makeSummary(id: String) -> TradeSummary {
        TradeSummary(
            id: TradeID(id),
            ownerProfileID: viewer,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            realizedPnL: Money(amount: 10, currencyCode: "USD"),
            riskReward: 2,
            points: 4,
            quantity: 1,
            entryAt: Date(timeIntervalSince1970: 1_700_000_000),
            exitAt: Date(timeIntervalSince1970: 1_700_000_600),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            visibility: .public,
            publicCaption: "Caption",
            notePreview: nil,
            thumbnail: nil,
            imageDisplayMode: .fit,
            mode: .live,
            publicAccountBadge: "Live",
            durationSeconds: 600,
            durationText: "10m"
        )
    }
}
