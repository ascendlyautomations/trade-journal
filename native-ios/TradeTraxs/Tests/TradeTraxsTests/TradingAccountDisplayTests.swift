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
        XCTAssertEqual(
            TradingAccountDisplay.title(
                name: "Apex 104582",
                accountNumber: "104582",
                audience: .public,
                category: .propFirm,
                mode: .evaluation
            ),
            "Evaluation Account"
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
        XCTAssertEqual(
            TradeDisplay.accountIdentityLine(
                name: "Apex 104582",
                mode: .evaluation,
                accountNumber: "104582",
                audience: .public,
                category: .propFirm
            ),
            "Evaluation Account"
        )
    }

    func testOwnerDropdownLineUsesLastFourDigitsWithoutBullets() {
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Alpha Futures",
                mode: .evaluation,
                accountNumber: "500123"
            ),
            "Alpha Futures · Eval · 0123"
        )
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Alpha Futures",
                mode: .evaluation,
                accountNumber: "3913"
            ),
            "Alpha Futures · Eval · 3913"
        )
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Alpha Futures",
                mode: .funded,
                accountNumber: "7293"
            ),
            "Alpha Futures · Funded · 7293"
        )
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "APEX475021000003",
                mode: .evaluation,
                accountNumber: "0000008591"
            ),
            "APEX475021000 · Eval · 8591"
        )
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Lucid",
                mode: .evaluation,
                accountNumber: "0001"
            ),
            "Lucid · Eval · 0001"
        )
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Test",
                mode: .funded,
                accountNumber: "0555"
            ),
            "Test · Funded · 0555"
        )
    }

    func testOwnerDropdownLineNormalizesAlreadyMaskedNumbersToLastFour() {
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Alpha Futures",
                mode: .evaluation,
                accountNumber: "••••0123"
            ),
            "Alpha Futures · Eval · 0123"
        )
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Tradovate Personal",
                mode: .live,
                accountNumber: "****0482"
            ),
            "Tradovate Per · Live · 0482"
        )
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Alpha Futures",
                mode: .evaluation,
                accountNumber: "•••• 0123"
            ),
            "Alpha Futures · Eval · 0123"
        )
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Alpha Futures",
                mode: .evaluation,
                accountNumber: "•••• •••• 0123"
            ),
            "Alpha Futures · Eval · 0123"
        )
    }

    func testOwnerDropdownLineShowsShortNumbersInFull() {
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Topstep",
                mode: .funded,
                accountNumber: "0123"
            ),
            "Topstep · Funded · 0123"
        )
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownLine(
                name: "Topstep",
                mode: .funded,
                accountNumber: "12"
            ),
            "Topstep · Funded · 12"
        )
    }

    func testOwnerDropdownDisplayNameTruncatesToThirteenCharactersWithoutEllipsis() {
        XCTAssertEqual(TradingAccountDisplay.ownerDropdownDisplayName("Alpha Futures"), "Alpha Futures")
        XCTAssertEqual(
            TradingAccountDisplay.ownerDropdownDisplayName("APEX475021000003"),
            "APEX475021000"
        )
    }

    func testInferPropFirmNameStripsTrailingSizeSuffix() {
        XCTAssertEqual(TradingAccountDisplay.inferPropFirmName("Alpha Futures 50K"), "Alpha Futures")
        XCTAssertEqual(TradingAccountDisplay.inferPropFirmName("Topstep $100K"), "Topstep")
        XCTAssertEqual(TradingAccountDisplay.inferPropFirmName("Apex"), "Apex")
        XCTAssertEqual(TradingAccountDisplay.inferPropFirmName("  "), "")
    }

    func testPropFirmNameOnlyForPropFirmCategory() {
        let prop = TradingAccount(
            id: TradingAccountID("p1"),
            ownerProfileID: ProfileID("u1"),
            name: "Tradeify 50K",
            category: .propFirm,
            mode: .evaluation,
            size: Money(amount: 50_000),
            isActive: true,
            canAddTrades: true
        )
        let personal = TradingAccount(
            id: TradingAccountID("p2"),
            ownerProfileID: ProfileID("u1"),
            name: "Tradeify 50K",
            category: .personal,
            mode: .live,
            size: Money(amount: 50_000),
            isActive: true,
            canAddTrades: true
        )
        XCTAssertEqual(TradingAccountDisplay.propFirmName(for: prop), "Tradeify")
        XCTAssertNil(TradingAccountDisplay.propFirmName(for: personal))
    }
}
