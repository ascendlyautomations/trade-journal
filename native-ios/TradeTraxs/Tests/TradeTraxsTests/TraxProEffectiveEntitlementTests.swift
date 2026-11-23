import XCTest
@testable import TradeTraxs

@MainActor
final class TraxProEffectiveEntitlementTests: XCTestCase {
    private let userID = "entitlement-test-user"

    override func setUp() {
        super.setUp()
        IosSubscriptionReleaseConfiguration.resetTestOverrides()
        MonetizationRuntimeConfiguration.shared.resetToFailClosed()
        SessionBillingEntitlementStore.shared.clear()
        PersistedEntitlementSnapshotStore.clear(userID: userID)
    }

    override func tearDown() {
        PersistedEntitlementSnapshotStore.clear(userID: userID)
        SessionBillingEntitlementStore.shared.clear()
        IosSubscriptionReleaseConfiguration.resetTestOverrides()
        MonetizationRuntimeConfiguration.shared.resetToFailClosed()
        super.tearDown()
    }

    func testUnknownAccessWhenEnforcementOnAndNoSnapshot() {
        IosSubscriptionReleaseConfiguration.setTestOverrides(paywall: true, enforcement: true)
        let profileID = ProfileID(userID)
        XCTAssertEqual(
            TraxProEffectiveEntitlement.clientAccess(profileID: profileID, demoModeActive: false),
            .unknown
        )
        XCTAssertTrue(
            ProMonetizationPolicy.shouldShowEntitlementVerification(
                demoModeActive: false,
                profileID: profileID
            )
        )
        XCTAssertFalse(
            ProMonetizationPolicy.shouldRestrictPremiumPsychologyAndAI(
                demoModeActive: false,
                profileID: profileID
            )
        )
        XCTAssertEqual(
            ProMonetizationPolicy.premiumFeaturePresentation(
                demoModeActive: false,
                profileID: profileID
            ),
            .verifyingEntitlement
        )
        XCTAssertFalse(
            ProMonetizationPolicy.shouldHidePremiumDashboardCharts(
                demoModeActive: false,
                profileID: profileID
            )
        )
    }

    func testVerifiedFreeRestrictsPremiumFeatures() {
        IosSubscriptionReleaseConfiguration.setTestOverrides(paywall: true, enforcement: true)
        let profileID = ProfileID(userID)
        let record = EntitlementSnapshotRecord(
            userID: userID,
            traxProActive: false,
            source: "none",
            accessExpiresAt: nil,
            revokedAt: nil,
            fetchedAt: Date()
        )
        PersistedEntitlementSnapshotStore.save(record)
        XCTAssertEqual(
            TraxProEffectiveEntitlement.clientAccess(profileID: profileID, demoModeActive: false),
            .free
        )
        XCTAssertTrue(
            ProMonetizationPolicy.shouldRestrictBacktestLab(
                demoModeActive: false,
                profileID: profileID
            )
        )
        XCTAssertEqual(
            ProMonetizationPolicy.premiumFeaturePresentation(
                demoModeActive: false,
                profileID: profileID
            ),
            .lockedPreview
        )
        XCTAssertTrue(
            ProMonetizationPolicy.shouldRestrictTradingRulesComplianceAnalytics(
                demoModeActive: false,
                profileID: profileID
            )
        )
    }

    func testVerifiedProUnlocksPremiumFeatures() {
        IosSubscriptionReleaseConfiguration.setTestOverrides(paywall: true, enforcement: true)
        let profileID = ProfileID(userID)
        let status = BillingStatus(
            profileID: profileID,
            plan: .pro,
            lifecycle: .active,
            isProEntitled: true,
            serverTraxProActive: true,
            accessExpiresAt: Date().addingTimeInterval(86_400),
            entitlementFetchedAt: Date()
        )
        SessionBillingEntitlementStore.shared.apply(status)
        XCTAssertEqual(
            TraxProEffectiveEntitlement.clientAccess(profileID: profileID, demoModeActive: false),
            .pro
        )
        XCTAssertEqual(
            ProMonetizationPolicy.premiumFeaturePresentation(
                demoModeActive: false,
                profileID: profileID
            ),
            .unrestricted
        )
        XCTAssertFalse(
            ProMonetizationPolicy.shouldRestrictTradingRulesComplianceAnalytics(
                demoModeActive: false,
                profileID: profileID
            )
        )
    }
}