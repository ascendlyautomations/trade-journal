import XCTest
@testable import TradeTraxs

final class TradingAccountDisplayTests: XCTestCase {
    func testOwnerTitleIncludesAccountNumber() {
        XCTAssertEqual(
            TradingAccountDisplay.title(
                name: "Alpha Futures",
                accountNumber: "500123",
                audience: .owner
            ),
            "Alpha Futures • 500123"
        )
        XCTAssertEqual(
            TradingAccountDisplay.title(
                name: "Apex",
                accountNumber: " 10482 ",
                audience: .owner
            ),
            "Apex • 10482"
        )
    }

    func testOwnerTitleOmitsMissingNumber() {
        XCTAssertEqual(
            TradingAccountDisplay.title(name: "Topstep", accountNumber: nil, audience: .owner),
            "Topstep"
        )
        XCTAssertEqual(
            TradingAccountDisplay.title(name: "Topstep", accountNumber: "  ", audience: .owner),
            "Topstep"
        )
    }

    func testPublicTitleNeverIncludesAccountNumber() {
        XCTAssertEqual(
            TradingAccountDisplay.title(
                name: "Alpha Futures",
                accountNumber: "500123",
                audience: .public
            ),
            "Alpha Futures"
        )
        let account = TradingAccount(
            id: TradingAccountID("a1"),
            ownerProfileID: ProfileID("u1"),
            name: "Topstep",
            category: .propFirm,
            mode: .funded,
            size: Money(amount: 50_000),
            isActive: true,
            canAddTrades: true,
            accountNumber: "77451"
        )
        XCTAssertEqual(
            TradingAccountDisplay.title(for: account, audience: .public),
            "Topstep"
        )
        XCTAssertEqual(
            TradingAccountDisplay.title(for: account, audience: .owner),
            "Topstep • 77451"
        )
    }

    func testTradeDisplayIdentityLineHonorsAudience() {
        XCTAssertEqual(
            TradeDisplay.accountIdentityLine(
                name: "Alpha Futures",
                size: 50_000,
                mode: .evaluation,
                accountNumber: "500123",
                audience: .owner
            ),
            "Alpha Futures • 500123"
        )
        XCTAssertEqual(
            TradeDisplay.accountIdentityLine(
                name: "Alpha Futures",
                size: 50_000,
                mode: .evaluation,
                accountNumber: "500123",
                audience: .public
            ),
            "Alpha Futures"
        )
    }
}
