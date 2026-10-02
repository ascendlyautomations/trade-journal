import XCTest
@testable import TradeTraxs

final class WithdrawalEditReconciliationTests: XCTestCase {
    func testAmountEditReplacesTheWithdrawalInsteadOfAddingAnother() {
        let accountID = TradingAccountID("acct")
        let original = entry(id: "w1", accountID: accountID, amount: 1_000)
        let corrected = entry(id: "w1", accountID: accountID, amount: 800, note: original.note)
        let starting: Decimal = 10_000
        let pnl: Decimal = 2_000

        let before = AccountTrackedBalanceSupport.ledgerTrackedBalance(
            startingBalance: starting,
            lifetimeRealizedPnL: pnl,
            payoutEntries: [original]
        )
        let after = AccountTrackedBalanceSupport.ledgerTrackedBalance(
            startingBalance: starting,
            lifetimeRealizedPnL: pnl,
            payoutEntries: [corrected]
        )

        XCTAssertEqual(before, 11_000)
        XCTAssertEqual(after, 11_200)
        XCTAssertEqual(
            AccountTrackedBalanceSupport.totalManualWithdrawals(from: [corrected]),
            800
        )
        XCTAssertNotEqual(
            AccountTrackedBalanceSupport.totalManualWithdrawals(from: [original, corrected]),
            800
        )
    }

    func testNoteAndImageDoNotChangeTrackedBalance() {
        let accountID = TradingAccountID("acct")
        let original = entry(id: "w1", accountID: accountID, amount: 1_000, note: "bank")
        let edited = entry(
            id: "w1",
            accountID: accountID,
            amount: 1_000,
            note: "updated note",
            imageURL: "https://example.com/storage/v1/object/public/screenshots/user/payouts/opt/1.jpg"
        )
        let balance = { (rows: [AccountPayoutEntry]) in
            AccountTrackedBalanceSupport.ledgerTrackedBalance(
                startingBalance: 5_000,
                lifetimeRealizedPnL: 0,
                payoutEntries: rows
            )
        }
        XCTAssertEqual(balance([original]), balance([edited]))
        XCTAssertEqual(balance([edited]), 4_000)
    }

    func testFailedImageReplacementKeepsThePreviousObject() {
        let previous = "https://cdn.example/storage/v1/object/public/screenshots/u/old.jpg"
        let uploaded = "https://cdn.example/storage/v1/object/public/screenshots/u/new.jpg"
        let plan = PayoutImageReplacementPlan.failedSave(uploadedURL: uploaded, previousURL: previous)
        XCTAssertEqual(plan.deleteURLs, [uploaded])
        XCTAssertEqual(plan.retainedURL, previous)
    }

    func testSuccessfulReplacementDeletesOnlyThePreviousObject() {
        let previous = "https://cdn.example/old.jpg"
        let saved = "https://cdn.example/new.jpg"
        let plan = PayoutImageReplacementPlan.succeeded(previousURL: previous, savedURL: saved)
        XCTAssertEqual(plan.deleteURLs, [previous])
        XCTAssertEqual(plan.retainedURL, saved)
    }

    func testNoteOnlySaveDoesNotDeleteTheImage() {
        let current = "https://cdn.example/same.jpg"
        let plan = PayoutImageReplacementPlan.succeeded(previousURL: current, savedURL: current)
        XCTAssertTrue(plan.deleteURLs.isEmpty)
        XCTAssertEqual(plan.retainedURL, current)
    }

    private func entry(
        id: String,
        accountID: TradingAccountID,
        amount: Decimal,
        note: String? = nil,
        imageURL: String? = nil
    ) -> AccountPayoutEntry {
        AccountPayoutEntry(
            id: AccountPayoutEntryID(id),
            accountID: accountID,
            amount: Money(amount: amount),
            payoutDate: Date(timeIntervalSince1970: 1_700_000_000),
            note: note,
            imageURL: imageURL
        )
    }
}
