import XCTest
@testable import TradeTraxs

final class TradeHistoryOwnerSeedTests: XCTestCase {
    func testCanSeedOnlyForDefaultQuery() {
        var query = TradeHistoryQuery()
        XCTAssertTrue(TradeHistoryOwnerSeed.canSeed(query: query, hasLocalBrowseConstraints: false))

        query.filters.account = .account(TradingAccountID("acct-1"))
        XCTAssertFalse(TradeHistoryOwnerSeed.canSeed(query: query, hasLocalBrowseConstraints: false))

        query = TradeHistoryQuery(searchText: "NQ")
        XCTAssertFalse(TradeHistoryOwnerSeed.canSeed(query: query, hasLocalBrowseConstraints: false))

        query = TradeHistoryQuery()
        XCTAssertFalse(TradeHistoryOwnerSeed.canSeed(query: query, hasLocalBrowseConstraints: true))
    }

    func testPageExcludesBacktestAndPreservesOrder() {
        let owner = ProfileID("viewer-1")
        let newest = makeTrade(id: "new", owner: owner, createdAt: Date(timeIntervalSince1970: 300), mode: .live)
        var backtest = makeTrade(id: "bt", owner: owner, createdAt: Date(timeIntervalSince1970: 250), mode: .backtest)
        backtest.mode = .backtest
        let mid = makeTrade(id: "mid", owner: owner, createdAt: Date(timeIntervalSince1970: 200), mode: .live)
        let oldest = makeTrade(id: "old", owner: owner, createdAt: Date(timeIntervalSince1970: 100), mode: .live)

        let result = TradeHistoryOwnerSeed.page(
            from: [backtest, newest, mid, oldest],
            query: TradeHistoryQuery(),
            limit: 2
        )

        XCTAssertEqual(result?.items.map(\.id.rawValue), ["new", "mid"])
        XCTAssertNotNil(result?.nextCursor)
        XCTAssertTrue(result?.isPartial == true)
    }

    func testEquivalentFiltersShareCacheKey() {
        let profile = ProfileID("p1")
        let a = TradeHistoryQuery(filters: TradeHistoryFilters(), searchText: "  ")
        let b = TradeHistoryQuery(filters: TradeHistoryFilters(), searchText: "")
        XCTAssertEqual(a.cacheKey(profileID: profile), b.cacheKey(profileID: profile))
    }

    private func makeTrade(id: String, owner: ProfileID, createdAt: Date, mode: TradeMode) -> Trade {
        Trade(
            id: TradeID(id),
            ownerProfileID: owner,
            accountID: nil,
            symbol: Symbol(ticker: "NQ"),
            side: .long,
            mode: mode,
            quantity: 1,
            entryPrice: nil,
            exitPrice: nil,
            entryAt: createdAt,
            exitAt: nil,
            realizedPnL: Money(amount: 10, currencyCode: "USD"),
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            strategy: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
