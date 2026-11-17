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
            fullTakeProfit: false,
            earlyExit: false,
            exitRrText: "",
            parsePoints: { Decimal(string: $0) },
            parseRr: { Decimal(string: $0) },
            canComputeExitRr: false,
            previewDraft: TradeDraft(
                symbol: Symbol(ticker: "MNQ"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryAt: Date(),
                realizedPnL: Money(amount: -50, currencyCode: "USD"),
                riskReward: 2,
                points: 40,
                visibility: .private
            )
        )
        XCTAssertNotNil(errors.maxRr)
        XCTAssertNil(errors.points)
        XCTAssertNil(errors.rr)
    }

    func testEarlyExitWinUsesPriceDerivedRealizedNotMax() {
        var draft = makeDraft(pnl: 100, rr: Decimal(2), points: 50, fullTp: false)
        draft.earlyExit = true
        draft.maxRrReached = Decimal(string: "1.5")
        draft.entryPrice = 20_000
        draft.exitPrice = 20_025
        let realized = TradePointsAndRealizedRr.realizedRrForManualSave(draft: draft)
        XCTAssertNotNil(realized)
        XCTAssertNotEqual(realized, draft.maxRrReached)
        XCTAssertNotEqual(realized, 2)
    }

    func testEarlyExitWinFallsBackToManualExitRr() {
        var draft = makeDraft(pnl: 100, rr: Decimal(2), points: 50, fullTp: false)
        draft.earlyExit = true
        draft.maxRrReached = Decimal(string: "1.5")
        draft.exitRr = Decimal(1)
        let realized = TradePointsAndRealizedRr.realizedRrForManualSave(draft: draft)
        XCTAssertEqual(realized, 1)
    }

    func testMutuallyExclusiveOutcomeFlagsRejected() {
        let errors = TradePointsAndRealizedRr.validateManualRiskFields(
            pnl: 100,
            pointsText: "50",
            rrText: "2",
            maxRrText: "1.5",
            fullTakeProfit: true,
            earlyExit: true,
            exitRrText: "",
            parsePoints: { Decimal(string: $0) },
            parseRr: { Decimal(string: $0) },
            canComputeExitRr: false,
            previewDraft: TradeDraft(
                symbol: Symbol(ticker: "MNQ"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryAt: Date(),
                realizedPnL: Money(amount: 100, currencyCode: "USD"),
                riskReward: 2,
                fullTakeProfit: true,
                earlyExit: true,
                points: 50,
                visibility: .private
            )
        )
        XCTAssertNotNil(errors.outcomeMode)
    }

    func testRealizedRrCannotExceedTargetedBlocksHighExitRr() {
        var draft = makeDraft(pnl: 100, rr: Decimal(2), points: 50, fullTp: false)
        draft.earlyExit = true
        draft.exitRr = Decimal(3)
        XCTAssertEqual(
            TradePointsAndRealizedRr.validateRealizedRrAgainstTargeted(draft: draft),
            TradePointsAndRealizedRr.realizedRrCannotExceedTargetedMessage
        )
    }

    func testRealizedRrMayEqualTargetedOnFullTp() {
        var draft = makeDraft(pnl: 100, rr: Decimal(2), points: 50, fullTp: true)
        XCTAssertNil(TradePointsAndRealizedRr.validateRealizedRrAgainstTargeted(draft: draft))
        XCTAssertEqual(TradePointsAndRealizedRr.realizedRrForManualSave(draft: draft), 2)
    }

    func testRealizedRrBelowTargetedIsAllowed() {
        var draft = makeDraft(pnl: 100, rr: Decimal(2), points: 50, fullTp: false)
        draft.earlyExit = true
        draft.exitRr = Decimal(1)
        XCTAssertNil(TradePointsAndRealizedRr.validateRealizedRrAgainstTargeted(draft: draft))
    }

    func testAverageRealizedRrUsesStoredValues() {
        let trades = [
            makeTrade(id: "a", realizedRr: 1, points: 10, riskReward: 2),
            makeTrade(id: "b", realizedRr: 3, points: 10, riskReward: 2),
        ]
        XCTAssertEqual(TradePointsAndRealizedRr.averageRealizedRr(trades: trades), 2)
    }

    func testAverageTargetedRrIgnoresMissingTarget() {
        let trades = [
            makeTrade(id: "a", realizedRr: 1, points: 10, riskReward: 2),
            makeTrade(id: "b", realizedRr: 1, points: 10, riskReward: nil as Decimal?),
            makeTrade(id: "c", realizedRr: 1, points: 10, riskReward: 4),
        ]
        XCTAssertEqual(TradePointsAndRealizedRr.averageTargetedRr(trades: trades), 3)
    }

    func testFullTpWinUsesTargetedRealizedRr() {
        var draft = makeDraft(pnl: 100, rr: Decimal(2), points: 50, fullTp: true)
        draft.entryPrice = 20_000
        draft.exitPrice = 20_010
        XCTAssertEqual(TradePointsAndRealizedRr.realizedRrForManualSave(draft: draft), 2)
    }

    func testPartialWinWithoutFullTpNeedsPrices() {
        var draft = makeDraft(pnl: 100, rr: Decimal(2), points: 50, fullTp: false)
        XCTAssertNil(TradePointsAndRealizedRr.realizedRrForManualSave(draft: draft))
        draft.entryPrice = 100
        draft.exitPrice = 125
        let realized = TradePointsAndRealizedRr.realizedRrForManualSave(draft: draft)
        XCTAssertEqual(realized, 1)
    }

    func testLossIgnoresFullTpFlag() {
        var draft = makeDraft(pnl: -50, rr: Decimal(2), points: 50, fullTp: true)
        draft.entryPrice = 20_000
        draft.exitPrice = 19_950
        let realized = TradePointsAndRealizedRr.realizedRrForManualSave(draft: draft)
        XCTAssertNotEqual(realized, 2)
    }

    private func makeDraft(
        pnl: Decimal,
        rr: Decimal?,
        points: Decimal,
        fullTp: Bool,
        earlyExit: Bool = false
    ) -> TradeDraft {
        TradeDraft(
            symbol: Symbol(ticker: "MNQ"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryAt: Date(),
            realizedPnL: Money(amount: pnl, currencyCode: "USD"),
            riskReward: rr,
            fullTakeProfit: fullTp,
            earlyExit: earlyExit,
            points: points,
            visibility: .private
        )
    }

    private func makeTrade(
        id: String,
        realizedRr: Decimal,
        points: Decimal,
        riskReward: Decimal?
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
