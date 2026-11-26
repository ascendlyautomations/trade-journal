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

    func testStandaloneMenuAccountsHideCopyLinkedRows() {
        let linkedA = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let linkedB = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let solo = TradingAccountID("cccccccc-cccc-cccc-cccc-cccccccccccc")
        let accounts = [
            account(id: linkedA, name: "Linked A"),
            account(id: linkedB, name: "Linked B"),
            account(id: solo, name: "Solo"),
        ]
        let groups = [
            CopyTradingGroup(
                id: "group-1",
                name: "Alpha",
                accountIDs: [linkedA.rawValue, linkedB.rawValue],
                createdAt: "",
                updatedAt: ""
            ),
        ]
        let menu = DashboardAccountFilterCopyTradingSupport.standaloneMenuAccounts(
            from: accounts,
            copyGroups: groups,
            preservingSelection: nil
        )
        XCTAssertEqual(menu.map(\.id), [solo])
    }

    func testSanitizedFilterDropsDeletedCopyGroup() {
        let accounts = [account(id: TradingAccountID("solo"), name: "Solo")]
        let sanitized = DashboardAccountFilterCopyTradingSupport.sanitizedFilter(
            .copyTradingGroup("removed-group"),
            accounts: accounts,
            copyGroups: []
        )
        XCTAssertEqual(sanitized, .all)
    }

    func testSanitizedFilterMigratesLinkedAccountToCopyScope() {
        let linked = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let accounts = [account(id: linked, name: "Linked")]
        let groups = [
            CopyTradingGroup(
                id: "group-1",
                name: "Alpha",
                accountIDs: [linked.rawValue],
                createdAt: "",
                updatedAt: ""
            ),
        ]
        let sanitized = DashboardAccountFilterCopyTradingSupport.sanitizedFilter(
            .account(linked),
            accounts: accounts,
            copyGroups: groups
        )
        XCTAssertEqual(sanitized, .copyTradingGroup("group-1"))
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

    private func account(id: TradingAccountID, name: String) -> TradingAccount {
        TradingAccount(
            id: id,
            ownerProfileID: ProfileID("11111111-1111-1111-1111-111111111111"),
            name: name,
            category: .personal,
            mode: .funded,
            size: nil,
            isActive: true,
            canAddTrades: true,
            accountNumber: nil
        )
    }
}
