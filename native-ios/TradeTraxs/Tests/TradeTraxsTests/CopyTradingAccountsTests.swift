import XCTest
@testable import TradeTraxs

final class CopyTradingAccountsTests: XCTestCase {
    func testGroupRequiresTwoOwnedAccounts() {
        let owned: Set<String> = ["a", "b", "c"]
        XCTAssertEqual(
            CopyTradingGroupRules.validationError(name: "Alpha", accountIDs: ["a"], ownedAccountIDs: owned),
            "Select at least two accounts."
        )
        XCTAssertEqual(
            CopyTradingGroupRules.validationError(name: "  ", accountIDs: ["a", "b"], ownedAccountIDs: owned),
            "Group name is required"
        )
        XCTAssertEqual(
            CopyTradingGroupRules.validationError(
                name: "Alpha",
                accountIDs: ["a", "foreign"],
                ownedAccountIDs: owned
            ),
            "You can only add accounts you own."
        )
        XCTAssertNil(
            CopyTradingGroupRules.validationError(name: "Alpha Funded Accounts", accountIDs: ["a", "b"], ownedAccountIDs: owned)
        )
    }

    func testFanoutMatchesWebCopyGroupSemantics() {
        let rows = CopyTradingTradeFanout.rows(
            groupID: "group-1",
            orderedAccountIDs: ["alpha-1", "alpha-2", "alpha-3"],
            pnl: 125
        )
        XCTAssertEqual(rows.map(\.accountID), ["alpha-1", "alpha-2", "alpha-3"])
        XCTAssertEqual(Set(rows.map(\.pnl)), [125])
        XCTAssertEqual(Set(rows.map(\.tradeMode)), ["copy_traded"])
        XCTAssertEqual(Set(rows.map(\.sourceAccountID)), ["alpha-1"])
        XCTAssertEqual(Set(rows.map(\.groupID)), ["group-1"])
        XCTAssertEqual(rows.map(\.copiedAccountIDs), [["alpha-2", "alpha-3"], ["alpha-2", "alpha-3"], ["alpha-2", "alpha-3"]])
        XCTAssertEqual(rows.count, 3)
    }

    func testDeletingAGroupDoesNotRemoveAccountsTradesOrBrokerConnections() {
        XCTAssertFalse(CopyTradingGroupDeletionEffect.removesTradingAccounts)
        XCTAssertFalse(CopyTradingGroupDeletionEffect.removesTrades)
        XCTAssertFalse(CopyTradingGroupDeletionEffect.removesBrokerConnections)
        XCTAssertTrue(CopyTradingGroupDeletionEffect.unlinksCopyTradingGroupID)
    }

    func testCopyTradingDeepLinkLandsUnderManageAccounts() {
        let parser = DeepLinkParser()
        let destination = parser.parse(url: URL(string: "tradetraxs://settings/copy-trading-groups")!)
        guard case .settingsStack(let routes) = destination else {
            return XCTFail("Expected settings stack")
        }
        XCTAssertEqual(routes, [.home, .tradingAccounts, .copyTradingAccounts])
        XCTAssertEqual(SettingsRoute.copyTradingAccounts.title, "Copy Trading Accounts")
    }
}
