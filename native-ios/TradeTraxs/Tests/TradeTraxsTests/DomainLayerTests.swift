import XCTest
@testable import TradeTraxs

final class DomainLayerTests: XCTestCase {
    func testAggregateOwnershipMapsTradeConcepts() {
        XCTAssertEqual(AggregateOwnership.owner(of: "Trade"), .trade)
        XCTAssertEqual(AggregateOwnership.owner(of: "Post"), .feed)
        XCTAssertEqual(AggregateOwnership.owner(of: "Conversation"), .messages)
        XCTAssertEqual(AggregateOwnership.owner(of: "TradeRoom"), .rooms)
        XCTAssertEqual(AggregateOwnership.owner(of: "Profile"), .profile)
        XCTAssertEqual(AggregateOwnership.owner(of: "HomeDashboard"), .home)
        XCTAssertNil(AggregateOwnership.owner(of: "UnknownThing"))
    }

    func testTradeDraftDefaultsAreBusinessConceptsOnly() {
        let draft = TradeDraft(
            accountID: TradingAccountID("a1"),
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 5000,
            exitPrice: 5010,
            entryAt: Date(timeIntervalSince1970: 0),
            exitAt: Date(timeIntervalSince1970: 60),
            realizedPnL: Money(amount: 100),
            visibility: .private,
            publicCaption: nil,
            noteBody: "plan followed"
        )
        XCTAssertEqual(draft.symbol.ticker, "ES")
        XCTAssertEqual(draft.side, .long)
    }

    func testDomainErrorDoesNotExposeNetworkTypes() {
        let error = DomainError.tradeValidation(.missingSymbol)
        let mapped = AppError.domain(error)
        if case .unknown = mapped {
            // expected bridge until richer AppError cases land
        } else {
            XCTFail("Expected AppError.unknown bridge")
        }
    }

    func testFreeTierPolicyCaps() {
        XCTAssertEqual(FreeTierPolicy.dailyTradeLimit, 3)
        XCTAssertEqual(FreeTierPolicy.maxTradeEntryAccounts, 3)
    }
}
