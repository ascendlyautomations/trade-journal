import XCTest
@testable import TradeTraxs

final class DashboardRrTargetAnalysisTests: XCTestCase {
    func testTargetAttainmentAbove100Percent() {
        let trade = makeTrade(id: "t1", target: 2, maxRr: 3, pnl: -10)
        let analysis = DashboardRrTargetAnalysis.compute(from: [trade])
        XCTAssertEqual(analysis.avgTargetAttainmentRatio, Decimal(string: "1.5"))
        XCTAssertTrue(
            analysis.bullets.joined(separator: " ").contains("150%")
                || analysis.bullets.joined(separator: " ").contains("above 100%")
        )
    }

    func testSmallSampleAvoidsProfitGuaranteeLanguage() {
        let trades = [
            makeTrade(id: "a", target: 5, maxRr: 1, pnl: -10),
            makeTrade(id: "b", target: 5, maxRr: 1, pnl: -20),
        ]
        let analysis = DashboardRrTargetAnalysis.compute(from: trades)
        XCTAssertLessThan(analysis.pairedCount, DashboardRrTargetAnalysis.minPairedRecommend)
        XCTAssertTrue(analysis.bullets.joined(separator: " ").contains("Early read"))
        XCTAssertFalse(analysis.bullets.joined(separator: " ").contains("profit guarantee"))
    }

    func testIncompleteTradesDoNotAffectPanelMetrics() {
        let trades = [
            makeTrade(id: "paired-a", target: 5, maxRr: Decimal(string: "2.5")!, pnl: -100),
            makeTrade(id: "paired-b", target: 5, maxRr: Decimal(string: "2.5")!, pnl: -50),
            makeTrade(id: "target-only", target: 10, maxRr: nil, pnl: 200),
        ]
        let analysis = DashboardRrTargetAnalysis.compute(from: trades)
        XCTAssertEqual(analysis.pairedCount, 2)
        XCTAssertEqual(analysis.avgTargetRr, 5)
        XCTAssertEqual(analysis.avgMaxRrReached, Decimal(string: "2.5"))
        XCTAssertEqual(analysis.avgTargetAttainmentRatio, Decimal(string: "0.5"))
        XCTAssertTrue(
            analysis.sampleSummary?.hasPrefix("Based on 2 trades with both values recorded.") == true
        )
    }

    func testMaxRrZeroIsEligible() {
        let trade = makeTrade(id: "t1", target: 3, maxRr: 0, pnl: -100)
        XCTAssertTrue(DashboardRrTargetAnalysis.isEligible(trade))
        let analysis = DashboardRrTargetAnalysis.compute(from: [trade])
        XCTAssertEqual(analysis.pairedCount, 1)
        XCTAssertEqual(analysis.avgMaxRrReached, 0)
    }

    func testOnlyTargetOrOnlyMaxExcluded() {
        XCTAssertFalse(
            DashboardRrTargetAnalysis.isEligible(
                makeTrade(id: "a", target: 2, maxRr: nil, pnl: 0)
            )
        )
        XCTAssertFalse(
            DashboardRrTargetAnalysis.isEligible(
                makeTrade(id: "b", target: nil, maxRr: 1, pnl: -10)
            )
        )
    }

    private func makeTrade(
        id: String,
        target: Decimal?,
        maxRr: Decimal?,
        pnl: Decimal
    ) -> Trade {
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
            riskReward: target,
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
