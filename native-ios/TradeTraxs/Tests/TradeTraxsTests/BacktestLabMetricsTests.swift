import XCTest
@testable import TradeTraxs

final class BacktestLabMetricsTests: XCTestCase {
    func testSnapshotCountsWinsAndLosses() {
        let trades = [
            makeTrade(pnl: 100, rr: 2),
            makeTrade(pnl: -50, rr: 1),
            makeTrade(pnl: 0, rr: nil),
        ]
        let snap = BacktestLabMetrics.snapshot(for: trades)
        XCTAssertEqual(snap.tradeCount, 3)
        XCTAssertEqual(snap.winCount, 1)
        XCTAssertEqual(snap.lossCount, 1)
        XCTAssertEqual(snap.totalPnL, 50)
        XCTAssertEqual(snap.averageRR ?? 0, 1.5, accuracy: 0.001)
    }

    func testBacktestLabTradeFilterUsesExecutionMode() {
        var live = makeTrade(pnl: 1, rr: 1)
        live.mode = .live
        let backtest = makeTrade(pnl: 2, rr: 2, strategy: "ORB")
        let filtered = [live, backtest].filter { $0.mode == .backtest }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.strategy, "ORB")
    }

    func testSnapshotProfitFactorAndAverages() {
        let trades = [
            makeTrade(pnl: 300, rr: 2),
            makeTrade(pnl: 100, rr: 1),
            makeTrade(pnl: -200, rr: 1),
        ]
        let snap = BacktestLabMetrics.snapshot(for: trades)
        XCTAssertEqual(snap.profitFactor, 2)
        XCTAssertEqual(snap.averageWin, 200)
        XCTAssertEqual(snap.averageLoss, 200)
    }

    func testSnapshotProfitFactorNilWithoutLosses() {
        let trades = [makeTrade(pnl: 50, rr: 1)]
        let snap = BacktestLabMetrics.snapshot(for: trades)
        XCTAssertNil(snap.profitFactor)
        XCTAssertEqual(snap.averageWin, 50)
        XCTAssertNil(snap.averageLoss)
    }

    func testBacktestLabFiltersAccountAndTime() {
        let accountA = TradingAccountID("acct-a")
        let accountB = TradingAccountID("acct-b")
        var tradeA = makeTrade(pnl: 10, rr: 1, strategy: "A")
        tradeA.accountID = accountA
        var tradeB = makeTrade(pnl: -5, rr: 1, strategy: "B")
        tradeB.accountID = accountB
        let filtered = BacktestLabFilters.apply(
            [tradeA, tradeB],
            accountFilter: .account(accountA),
            strategy: BacktestLabMetrics.allStrategiesToken,
            timeFilter: .allTime,
            customInterval: nil
        )
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.accountID, accountA)
    }

    func testStrategyFilterAndBreakdown() {
        let all = [
            makeTrade(pnl: 10, rr: 1, strategy: "Opening Drive"),
            makeTrade(pnl: -5, rr: 2, strategy: "Opening Drive"),
            makeTrade(pnl: 20, rr: 3, strategy: "Fade"),
        ]

        let filtered = BacktestLabMetrics.filter(all, strategy: "Fade")
        XCTAssertEqual(filtered.count, 1)

        let breakdown = BacktestLabMetrics.strategyBreakdown(from: all)
        XCTAssertEqual(breakdown.count, 2)
        XCTAssertEqual(breakdown.first(where: { $0.name == "Fade" })?.tradeCount, 1)
    }

    private func makeTrade(pnl: Double, rr: Double?, strategy: String? = nil) -> Trade {
        let now = Date()
        return Trade(
            id: TradeID(UUID().uuidString),
            ownerProfileID: ProfileID(UUID().uuidString),
            accountID: nil,
            symbol: Symbol(ticker: "MNQ"),
            side: .long,
            mode: .backtest,
            quantity: 1,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: now,
            exitAt: now,
            realizedPnL: Money(amount: Decimal(pnl)),
            riskReward: rr.map { Decimal($0) },
            points: nil,
            sessionLabel: nil,
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            strategy: strategy,
            createdAt: now,
            updatedAt: now
        )
    }
}
