import XCTest
@testable import TradeTraxs

final class FreePlanTradeAccountPolicyTests: XCTestCase {
    func testCreationLimitCountsAllAccountsIncludingReadOnly() {
        let owner = ProfileID("policy.owner")
        let accounts = [
            makeAccount(id: "1", owner: owner, canAdd: true),
            makeAccount(id: "2", owner: owner, canAdd: false),
            makeAccount(id: "3", owner: owner, canAdd: false),
        ]
        XCTAssertFalse(
            FreePlanTradeAccountPolicy.canCreateAnotherAccount(accounts: accounts, viewerTier: .free)
        )
        XCTAssertEqual(FreePlanTradeAccountPolicy.countTradeEntryEnabled(accounts), 1)
    }

    func testSlotSelectionWhenMoreThanThreeEntryEnabled() {
        let owner = ProfileID("policy.slots")
        let accounts = (1 ... 4).map { index in
            makeAccount(id: "a\(index)", owner: owner, canAdd: true)
        }
        XCTAssertTrue(
            FreePlanTradeAccountPolicy.needsSlotSelection(accounts: accounts, viewerTier: .free)
        )
        XCTAssertFalse(
            FreePlanTradeAccountPolicy.needsSlotSelection(accounts: accounts, viewerTier: .pro)
        )
    }

    private func makeAccount(id: String, owner: ProfileID, canAdd: Bool) -> TradingAccount {
        TradingAccount(
            id: TradingAccountID(id),
            ownerProfileID: owner,
            name: id,
            category: .personal,
            mode: .live,
            size: Money(amount: 25_000),
            isActive: true,
            canAddTrades: canAdd,
            showInAccountDropdowns: true
        )
    }
}
