import XCTest
@testable import TradeTraxs

@MainActor
final class TradeEntryEntitlementGateTests: XCTestCase {
    override func tearDown() {
        SessionBootstrapStore.shared.clear()
        IosSubscriptionReleaseConfiguration.resetTestOverrides()
        MonetizationRuntimeConfiguration.shared.resetToFailClosed()
        super.tearDown()
    }

    func testFreeViewerBlocksReadOnlyAccountWhenEnforcementOn() {
        IosSubscriptionReleaseConfiguration.setTestOverrides(paywall: nil, enforcement: true)
        let owner = ProfileID("user.copy.gate")
        let accounts = [
            makeAccount(id: "a1", owner: owner, canAdd: true),
            makeAccount(id: "a2", owner: owner, canAdd: false),
        ]
        SessionBootstrapStore.shared.clear()
        PersistedEntitlementSnapshotStore.clear(userID: owner.rawValue)

        XCTAssertNil(TradeEntryEntitlementGate.validateAccountsForNewTrades(accounts, profileID: owner))
        XCTAssertFalse(
            TradeEntryEntitlementGate.accountAllowsNewTrade(accounts[1], viewerTier: .free)
        )
    }

    func testEnforcementOffIgnoresCanAddTradesForFreeViewer() {
        IosSubscriptionReleaseConfiguration.setTestOverrides(paywall: nil, enforcement: false)
        let owner = ProfileID("user.copy.gate.off")
        let accounts = [
            makeAccount(id: "a1", owner: owner, canAdd: false),
        ]
        XCTAssertTrue(
            TradeEntryEntitlementGate.accountAllowsNewTrade(accounts[0], viewerTier: .free)
        )
        XCTAssertNil(TradeEntryEntitlementGate.validateAccountsForNewTrades(accounts, profileID: owner))
    }

    func testProViewerAllowsReadOnlyFlagAccounts() {
        let owner = ProfileID("user.copy.pro")
        PersistedEntitlementSnapshotStore.save(
            EntitlementSnapshotRecord(
                userID: owner.rawValue,
                traxProActive: true,
                source: TraxProEntitlementSource.apple.rawValue,
                accessExpiresAt: Date().addingTimeInterval(86_400),
                revokedAt: nil,
                fetchedAt: Date()
            )
        )
        let accounts = [
            makeAccount(id: "a1", owner: owner, canAdd: true),
            makeAccount(id: "a2", owner: owner, canAdd: false),
        ]

        XCTAssertNil(TradeEntryEntitlementGate.validateAccountsForNewTrades(accounts, profileID: owner))
        XCTAssertTrue(
            TradeEntryEntitlementGate.accountAllowsNewTrade(
                accounts[1],
                viewerTier: .pro
            )
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
