import XCTest
@testable import TradeTraxs

final class TradeMaxRrReachedMetricsTests: XCTestCase {
    func testAverageMaxRrReachedIgnoresMissingValues() {
        let loss = makeTrade(id: "l1", pnl: -100, maxRr: 2)
        let loss2 = makeTrade(id: "l2", pnl: -50, maxRr: 4)
        let win = makeTrade(id: "w1", pnl: 200, maxRr: nil)
        let summary = DashboardChartMetrics.compute(
            from: [loss, loss2, win].map {
                DashboardChartMetrics.Input(trade: $0, accountType: nil)
            },
            accountFilter: .all,
            dateRange: .all
        )
        XCTAssertEqual(summary.averageMaxRrReached, 3)
    }

    func testAverageMaxRrReachedNilWhenNoneRecorded() {
        let trade = makeTrade(id: "t1", pnl: -10, maxRr: nil)
        let summary = DashboardChartMetrics.compute(
            from: [DashboardChartMetrics.Input(trade: trade, accountType: nil)],
            accountFilter: .all,
            dateRange: .all
        )
        XCTAssertNil(summary.averageMaxRrReached)
    }

    private func makeTrade(id: String, pnl: Decimal, maxRr: Decimal?) -> Trade {
        Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID("owner"),
            accountID: nil,
            symbol: Symbol(ticker: "NQ"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: nil,
            exitPrice: nil,
            entryAt: Date(),
            exitAt: Date(),
            realizedPnL: Money(amount: pnl, currencyCode: "USD"),
            riskReward: nil,
            maxRrReached: maxRr,
            points: nil,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
