import XCTest
@testable import TradeTraxs

final class JournalTradeShareSupportTests: XCTestCase {
    func testJournalShareTargetUsesTradeWebURL() {
        let trade = Trade(
            id: TradeID("trade-private-1"),
            ownerProfileID: ProfileID("owner-1"),
            symbol: Symbol(ticker: "NQ"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 18_000,
            exitPrice: 18_050,
            entryAt: .now,
            exitAt: .now,
            realizedPnL: Money(amount: 250),
            visibility: .private,
            createdAt: .now,
            updatedAt: .now
        )
        let presentation = JournalTradeShareSupport.presentation(for: trade)
        XCTAssertEqual(presentation.ownerAccess.visibility, .private)
        XCTAssertEqual(
            presentation.target.contentLink.absoluteString,
            "https://www.tradetraxs.com/trade/trade-private-1"
        )
        if case .trade(let tradeID) = presentation.target.reference {
            XCTAssertEqual(tradeID, trade.id)
        } else {
            XCTFail("expected trade reference")
        }
    }

    func testMakePublicDraftOverridesVisibility() {
        let trade = Trade(
            id: TradeID("trade-2"),
            ownerProfileID: ProfileID("owner-1"),
            symbol: Symbol(ticker: "ES"),
            side: .short,
            mode: .live,
            quantity: 2,
            entryPrice: 5_100,
            exitPrice: 5_090,
            entryAt: .now,
            exitAt: .now,
            realizedPnL: Money(amount: -80),
            visibility: .private,
            createdAt: .now,
            updatedAt: .now
        )
        let draft = JournalTradeShareSupport.tradeDraft(from: trade, visibility: .public)
        XCTAssertEqual(draft.visibility, .public)
        XCTAssertEqual(draft.symbol.ticker, "ES")
    }
}