import XCTest
@testable import TradeTraxs

final class AccountNumberPrivacyContractTests: XCTestCase {
    func testPublicProfileInsightWireContainsNoAccountNumberKey() throws {
        let json = """
        {"meta":{"contract_version":1,"found":true,"can_view":true,"is_own":false},"data":{"accounts":[{"id":"a1","name":"Evaluation Account","category":"Prop Firm","type":"Eval","custom_status":null,"payout_total":0,"payouts":[]}]}}
        """
        XCTAssertFalse(PublicAccountPrivacy.jsonContainsForbiddenAccountIdentifier(json))
        let insights = try ProfileAccountInsightMapper.mapAccounts(from: Data(json.utf8))
        XCTAssertEqual(insights.first?.name, "Evaluation Account")
    }

    func testForbiddenAccountIdentifierKeysDetectedInJSON() {
        let leaking = """
        {"accounts":[{"id":"a1","name":"Main","account_number":"104582"}]}
        """
        XCTAssertTrue(PublicAccountPrivacy.jsonContainsForbiddenAccountIdentifier(leaking))

        let tradeLeak = """
        {"id":"t1","account_name":"Alpha","account_id":"acc-1"}
        """
        XCTAssertTrue(PublicAccountPrivacy.jsonContainsForbiddenAccountIdentifier(tradeLeak))
    }

    func testPublicSafeNameRedactsEmbeddedAccountNumber() {
        let safe = PublicAccountPrivacy.publicSafeAccountName(
            rawName: "Apex 104582",
            accountNumber: "104582",
            category: .propFirm,
            mode: .evaluation
        )
        XCTAssertEqual(safe, "Evaluation Account")
        XCTAssertFalse(safe.contains("104582"))
    }

    func testOwnerAccountMapperRetainsAccountNumber() throws {
        let dto = TradeDTO.Account(
            id: "acc-1",
            user_id: "user-1",
            name: "Alpha Futures",
            account_name: nil,
            account_type: nil,
            category: "Personal",
            mode: "Live",
            account_size: FlexibleNumber(50_000),
            size: nil,
            account_number: "500123",
            note: nil,
            is_active: true,
            can_add_trades: true,
            show_in_account_dropdowns: true,
            custom_public_status: nil,
            consistency: nil,
            max_drawdown: nil,
            daily_drawdown: nil,
            profit_target: nil,
            winning_days: nil,
            winning_day_threshold: nil,
            payout_drawdown_behavior: nil
        )
        let account = try TradingAccountMapper.mapToDomain(dto)
        XCTAssertEqual(account.accountNumber, "500123")
        XCTAssertEqual(
            TradingAccountDisplay.title(for: account, audience: .owner),
            "Alpha Futures • 500123"
        )
    }

    func testPublicTradeInsertBodyOmitsOwnerIdentifiers() {
        let body = TradeMapper.insertBody(
            from: TradeDraft(
                accountID: TradingAccountID("acc-1"),
                accountName: "Apex 104582",
                accountSizeLabel: "50000",
                accountModeLabel: "Eval",
                accountCategoryLabel: "Prop Firm",
                ownerAccountNumber: "104582",
                ownerAccountCategory: .propFirm,
                ownerAccountMode: .evaluation,
                symbol: Symbol(ticker: "NQ"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryAt: Date(),
                visibility: .public
            ),
            userID: UserID("user-1")
        )
        XCTAssertEqual(body.account_name, "Evaluation Account")
        XCTAssertNil(body.account_size)
    }

    func testProfileTradeDisplayNeverUsesOwnerAudience() {
        XCTAssertEqual(
            TradingAccountDisplay.title(
                name: "Alpha Futures",
                accountNumber: "500123",
                audience: .public,
                category: .personal,
                mode: .live
            ),
            "Alpha Futures"
        )
        XCTAssertEqual(
            PublicAccountPrivacy.publicTradeAccountLabel(mode: .live),
            "Live Account"
        )
    }
}
