import XCTest
@testable import TradeTraxs

final class TradePointsAndRealizedRrTests: XCTestCase {
    func testComputeActualPointsExamples() {
        var loss = makeTrade(id: "t1", realizedRr: -1, points: 50, riskReward: 2.5)
        XCTAssertEqual(
            TradePointsAndRealizedRr.computeActualPoints(trade: loss),
            Decimal(-20)
        )

        var win = loss
        win.realizedRr = Decimal(string: "1.5")
        XCTAssertEqual(
            TradePointsAndRealizedRr.computeActualPoints(trade: win),
            Decimal(30)
        )

        win.realizedRr = 0
        XCTAssertEqual(
            TradePointsAndRealizedRr.computeActualPoints(trade: win),
            0
        )
    }

    func testValidateManualRiskFieldsRequiresMaxOnLoss() {
        let errors = TradePointsAndRealizedRr.validateManualRiskFields(
            pnl: -50,
            pointsText: "40",
            rrText: "2",
            maxRrText: "",
            parsePoints: { Decimal(string: $0) },
            parseRr: { Decimal(string: $0) }
        )
        XCTAssertNotNil(errors.maxRr)
        XCTAssertNil(errors.points)
        XCTAssertNil(errors.rr)
    }

    func testAverageRealizedRrUsesStoredValues() {
        let trades = [
            makeTrade(id: "a", realizedRr: 1, points: 10, riskReward: 2),
            makeTrade(id: "b", realizedRr: 3, points: 10, riskReward: 2),
        ]
        XCTAssertEqual(TradePointsAndRealizedRr.averageRealizedRr(trades: trades), 2)
    }

    private func makeTrade(
        id: String,
        realizedRr: Decimal,
        points: Decimal,
        riskReward: Decimal
    ) -> Trade {
        Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID("owner"),
            accountID: nil,
            symbol: Symbol(ticker: "MNQ"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: nil,
            exitPrice: nil,
            entryAt: Date(),
            exitAt: Date(),
            realizedPnL: Money(amount: -100, currencyCode: "USD"),
            riskReward: riskReward,
            maxRrReached: 0,
            realizedRr: realizedRr,
            points: points,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
