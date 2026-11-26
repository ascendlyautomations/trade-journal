import XCTest
@testable import TradeTraxs

final class ClipLinkedTradePresentationTests: XCTestCase {
    func testOmitsHiddenPricesAndExitTimeWhenAbsent() {
        var trade = ProfileTradeFixtures.samples(owner: ProfileID("clip.linked"))[0]
        trade.entryPrice = 21_450.25
        trade.exitPrice = nil
        trade.exitAt = nil
        trade.riskReward = nil
        trade.realizedRr = nil
        trade.publicAccountBadge = nil

        let fields = ClipLinkedTradePresentation.fields(for: trade)

        XCTAssertEqual(fields.entryPrice, TradeDisplay.executionPriceText(21_450.25, display: .fullPrecision))
        XCTAssertNil(fields.exitPrice)
        XCTAssertNil(fields.exitTime)
        XCTAssertNil(fields.targetedRr)
        XCTAssertNil(fields.realizedRr)
        XCTAssertNil(fields.accountCaption)
    }

    func testIncludesTargetedAndRealizedRrWhenPresent() {
        var trade = ProfileTradeFixtures.samples(owner: ProfileID("clip.linked"))[0]
        trade.riskReward = 2.5
        trade.realizedRr = 1.5

        let fields = ClipLinkedTradePresentation.fields(for: trade)

        XCTAssertEqual(fields.targetedRr, "+2.5R")
        XCTAssertEqual(fields.realizedRr, "+1.5R")
    }
}