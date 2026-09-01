import XCTest
@testable import TradeTraxs

final class PublicTradeAccountBadgeTests: XCTestCase {
    func testBadgeLabelsFromAuthoritativeModeFields() {
        XCTAssertEqual(PublicTradeAccountBadge.label(tradeMode: "eval", accountType: nil), "Eval")
        XCTAssertEqual(PublicTradeAccountBadge.label(tradeMode: "evaluation", accountType: nil), "Eval")
        XCTAssertEqual(PublicTradeAccountBadge.label(tradeMode: "funded", accountType: nil), "Funded")
        XCTAssertEqual(PublicTradeAccountBadge.label(tradeMode: "live", accountType: nil), "Live")
        XCTAssertEqual(PublicTradeAccountBadge.label(tradeMode: "backtest", accountType: nil), "Backtest")
        XCTAssertEqual(PublicTradeAccountBadge.label(tradeMode: "sim", accountType: nil), "Sim")
        XCTAssertEqual(PublicTradeAccountBadge.label(tradeMode: "personal", accountType: nil), "Live")
        XCTAssertEqual(PublicTradeAccountBadge.label(tradeMode: "broker", accountType: nil), "Live")
    }

    func testBadgeOmitsCategoryOnlyAndUnknownValues() {
        XCTAssertNil(PublicTradeAccountBadge.label(tradeMode: "prop firm", accountType: nil))
        XCTAssertNil(PublicTradeAccountBadge.label(tradeMode: "prop_firm", accountType: nil))
        XCTAssertNil(PublicTradeAccountBadge.label(tradeMode: nil, accountType: "Prop Firm"))
        XCTAssertNil(PublicTradeAccountBadge.label(tradeMode: "imported", accountType: nil))
        XCTAssertNil(PublicTradeAccountBadge.label(tradeMode: "unknown_mode", accountType: nil))
    }

    func testModePreferredOverAccountTypeCategory() {
        XCTAssertEqual(
            PublicTradeAccountBadge.label(tradeMode: "eval", accountType: "Prop Firm"),
            "Eval"
        )
    }

    func testTradeMapperSetsPublicAccountBadgeFromWireFields() throws {
        var dto = TradeDTO.Trade()
        dto.id = "trade-badge-1"
        dto.user_id = "user-1"
        dto.ticker = "NQ"
        dto.direction = "long"
        dto.mode = "funded"
        dto.account_type = "Prop Firm"
        dto.created_at = "2026-01-15T12:00:00Z"
        dto.is_public = true

        let trade = try TradeMapper.mapToDomain(dto)
        XCTAssertEqual(trade.publicAccountBadge, "Funded")
    }

    func testPublicTradeWireContainsModeWithoutAccountNumber() {
        let publicTradeJSON = """
        {"id":"t1","user_id":"u1","ticker":"NQ","direction":"long","mode":"eval","account_type":"Prop Firm","pnl":1200,"rr":2.1,"contracts":1,"created_at":"2026-01-15T12:00:00Z","is_public":true}
        """
        XCTAssertFalse(PublicAccountPrivacy.jsonContainsForbiddenAccountIdentifier(publicTradeJSON))
        XCTAssertTrue(publicTradeJSON.contains("\"mode\":\"eval\""))
    }
}
