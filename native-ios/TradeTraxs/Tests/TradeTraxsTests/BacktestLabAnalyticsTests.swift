import XCTest
@testable import TradeTraxs

final class BacktestLabAnalyticsTests: XCTestCase {
    func testGroupedPerformanceStrategyAndSetupTags() {
        let owner = ProfileID("owner")
        let account = TradingAccountID("bt-1")
        let trades: [Trade] = [
            makeTrade(owner: owner, account: account, strategy: "ORB, VWAP", pnl: 100),
            makeTrade(owner: owner, account: account, strategy: "ORB", pnl: -50),
        ]

        let strategies = BacktestLabGroupedPerformance.strategyRows(from: trades)
        XCTAssertEqual(strategies.count, 2)

        let tags = BacktestLabGroupedPerformance.setupTagRows(from: trades)
        XCTAssertTrue(tags.contains { $0.key == "orb" })
        XCTAssertTrue(tags.contains { $0.key == "vwap" })
    }

    func testDrillDownWinsFilter() {
        let wins = BacktestLabChartDrillDown.wins.filter([
            makeTrade(owner: ProfileID("o"), account: TradingAccountID("a"), strategy: nil, pnl: 10),
            makeTrade(owner: ProfileID("o"), account: TradingAccountID("a"), strategy: nil, pnl: -1),
        ])
        XCTAssertEqual(wins.count, 1)
    }

    func testLifetimeScopedTradesPreservesPrePeriodForEquity() {
        let accounts = [
            TradingAccount(
                id: TradingAccountID("a"),
                ownerProfileID: ProfileID("o"),
                name: "BT",
                category: .backtest,
                mode: .backtest,
                size: Money(amount: 10_000),
                isActive: true,
                canAddTrades: true
            ),
        ]
        let ids = BacktestLabFilters.backtestModeAccountIDs(from: accounts)
        let early = Date(timeIntervalSince1970: 1_000_000)
        let late = Date(timeIntervalSince1970: 2_000_000)
        let trades = [
            makeTrade(owner: ProfileID("o"), account: TradingAccountID("a"), strategy: nil, pnl: 500, entry: early),
            makeTrade(owner: ProfileID("o"), account: TradingAccountID("a"), strategy: nil, pnl: -100, entry: late),
        ]

        let lifetime = BacktestLabFilters.lifetimeScopedTrades(
            trades,
            accountFilter: .all,
            strategy: BacktestLabMetrics.allStrategiesToken,
            backtestModeAccountIDs: ids
        )
        XCTAssertEqual(lifetime.count, 2)

        let periodOnly = BacktestLabFilters.apply(
            trades,
            accountFilter: .all,
            strategy: BacktestLabMetrics.allStrategiesToken,
            timeFilter: .last30Days,
            customInterval: nil,
            backtestModeAccountIDs: ids
        )
        _ = periodOnly
    }

    private func makeTrade(
        owner: ProfileID,
        account: TradingAccountID,
        strategy: String?,
        pnl: Decimal,
        entry: Date = Date()
    ) -> Trade {
        Trade(
            id: TradeID(UUID().uuidString),
            ownerProfileID: owner,
            accountID: account,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .backtest,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: entry,
            exitAt: entry,
            realizedPnL: Money(amount: pnl),
            riskReward: 2,
            visibility: .private,
            strategy: strategy,
            createdAt: entry,
            updatedAt: entry
        )
    }
}