import XCTest
@testable import TradeTraxs

final class MonetizationReadinessTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "MonetizationReadinessTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        IosSubscriptionReleaseConfiguration.resetTestOverrides()
        MonetizationRuntimeConfiguration.shared.resetToFailClosed()
    }

    override func tearDown() {
        IosSubscriptionReleaseConfiguration.resetTestOverrides()
        MonetizationRuntimeConfiguration.shared.resetToFailClosed()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMissingConfigStaysFailClosed() {
        XCTAssertFalse(IosSubscriptionReleaseConfiguration.iosPaywallEnabled)
        XCTAssertFalse(IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled)
        XCTAssertFalse(IosSubscriptionReleaseConfiguration.appliesFreeTierUsageCaps)
    }

    func testSuccessfulFetchCanEnablePaywallWithoutEnforcement() {
        let userID = UUID().uuidString
        MonetizationRuntimeConfiguration.shared.restoreCache(userID: userID)
        MonetizationRuntimeConfiguration.shared.applySuccessfulFetch(
            CachedMonetizationFlags(iosPaywallEnabled: true, entitlementEnforcementEnabled: false),
            userID: userID
        )
        XCTAssertTrue(IosSubscriptionReleaseConfiguration.iosPaywallEnabled)
        XCTAssertFalse(IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled)
    }

    func testBothFlagsCanBeEnabledTogether() {
        let userID = UUID().uuidString
        MonetizationRuntimeConfiguration.shared.applySuccessfulFetch(
            CachedMonetizationFlags(iosPaywallEnabled: true, entitlementEnforcementEnabled: true),
            userID: userID
        )
        XCTAssertTrue(IosSubscriptionReleaseConfiguration.iosPaywallEnabled)
        XCTAssertTrue(IosSubscriptionReleaseConfiguration.appliesFreeTierUsageCaps)
    }

    func testMalformedCacheDoesNotEnableMonetization() {
        let userID = UUID().uuidString
        defaults.set(Data("not-json".utf8), forKey: MonetizationRuntimeConfiguration.cacheKey(userID: userID))
        XCTAssertNil(MonetizationRuntimeConfiguration.load(userID: userID, defaults: defaults))
    }

    func testCachedFlagsRoundTrip() {
        let userID = UUID().uuidString
        let flags = CachedMonetizationFlags(iosPaywallEnabled: true, entitlementEnforcementEnabled: false)
        MonetizationRuntimeConfiguration.save(flags, userID: userID, defaults: defaults)
        XCTAssertEqual(MonetizationRuntimeConfiguration.load(userID: userID, defaults: defaults), flags)
    }

    func testOfflineValidAppleSnapshotKeepsPro() {
        let record = EntitlementSnapshotRecord(
            userID: "user",
            traxProActive: true,
            source: "apple",
            accessExpiresAt: Date().addingTimeInterval(86_400),
            revokedAt: nil,
            fetchedAt: Date().addingTimeInterval(-86_400 * 30)
        )
        XCTAssertEqual(EntitlementSnapshotPolicy.decision(record), .grant)
    }

    func testExpiredSnapshotDeniesPro() {
        let record = EntitlementSnapshotRecord(
            userID: "user",
            traxProActive: true,
            source: "apple",
            accessExpiresAt: Date().addingTimeInterval(-60),
            revokedAt: nil,
            fetchedAt: Date().addingTimeInterval(-120)
        )
        XCTAssertEqual(EntitlementSnapshotPolicy.decision(record), .deny)
    }

    func testRevokedSnapshotDeniesPro() {
        let record = EntitlementSnapshotRecord(
            userID: "user",
            traxProActive: true,
            source: "apple",
            accessExpiresAt: Date().addingTimeInterval(86_400),
            revokedAt: Date(),
            fetchedAt: Date()
        )
        XCTAssertEqual(EntitlementSnapshotPolicy.decision(record), .deny)
    }

    func testColdLaunchWithoutCacheDoesNotGrantPro() {
        XCTAssertEqual(EntitlementSnapshotPolicy.decision(nil), .unavailable)
    }

    func testNonExpiringGrantExpiresAfterOfflineGrace() {
        let fresh = EntitlementSnapshotRecord(
            userID: "user",
            traxProActive: true,
            source: "manual",
            accessExpiresAt: nil,
            revokedAt: nil,
            fetchedAt: Date()
        )
        let stale = EntitlementSnapshotRecord(
            userID: "user",
            traxProActive: true,
            source: "manual",
            accessExpiresAt: nil,
            revokedAt: nil,
            fetchedAt: Date().addingTimeInterval(-(EntitlementSnapshotPolicy.nonExpiringOfflineGrace + 60))
        )
        XCTAssertEqual(EntitlementSnapshotPolicy.decision(fresh), .grant)
        XCTAssertEqual(EntitlementSnapshotPolicy.decision(stale), .unavailable)
    }

    func testIntroductoryOfferCopyComesFromStoreKitPeriod() {
        XCTAssertEqual(
            IntroductoryOfferCopy.summary(
                paymentMode: .freeTrial,
                periodValue: 14,
                periodUnit: .day,
                displayPrice: "$0.00"
            ),
            "14 days free trial"
        )
        XCTAssertNil(
            IntroductoryOfferCopy.summary(
                paymentMode: .payAsYouGo,
                periodValue: 1,
                periodUnit: .month,
                displayPrice: "  "
            )
        )
    }

    func testServerSnapshotBeatsLocalFreeFields() {
        var status = BillingStatus(
            profileID: ProfileID("user"),
            plan: .free,
            lifecycle: .none,
            isProEntitled: false,
            entitlementSource: .apple,
            serverTraxProActive: true,
            accessExpiresAt: Date().addingTimeInterval(86_400),
            entitlementFetchedAt: Date()
        )
        XCTAssertTrue(status.hasTraxProAccess)
        status.serverTraxProActive = false
        XCTAssertFalse(status.hasTraxProAccess)
    }

    func testMonthlyStoreKitIdentifierUsesReplacementProductID() {
        let monthly = "com.tradetraxs.traxspro.monthly"
        XCTAssertEqual(TraxProProductConfiguration.defaultMonthlyProductID, monthly)
        XCTAssertEqual(TraxProProductConfiguration.billingInterval(for: monthly), .monthly)
        XCTAssertNil(
            TraxProProductConfiguration.billingInterval(for: "com.tradetraxs.traxpro.monthly")
        )
        XCTAssertEqual(TraxProProductConfiguration.allProductIDs, [
            TraxProProductConfiguration.monthlyProductID,
            TraxProProductConfiguration.sixMonthProductID,
            TraxProProductConfiguration.yearlyProductID,
        ])
        XCTAssertTrue(TraxProProductConfiguration.allProductIDs.contains(monthly))
        XCTAssertFalse(
            TraxProProductConfiguration.allProductIDs.contains("com.tradetraxs.traxpro.monthly")
        )
        XCTAssertEqual(TraxProProductConfiguration.sixMonthProductID, "com.tradetraxs.traxpro.sixmonth")
        XCTAssertEqual(TraxProProductConfiguration.yearlyProductID, "com.tradetraxs.traxpro.yearly")
    }
}
