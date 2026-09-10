import XCTest
@testable import TradeTraxs

final class TraxProEntitlementResolverTests: XCTestCase {
    private let future = Date().addingTimeInterval(86_400)
    private let past = Date().addingTimeInterval(-86_400)

    func testStripeActiveUserRemainsPro() {
        let status = makeStatus(
            lifecycle: .active,
            subscriptionStatusRaw: "active"
        )
        let resolution = TraxProEntitlementResolver.resolve(status)
        XCTAssertTrue(resolution.isActive)
        XCTAssertEqual(resolution.source, TraxProEntitlementSource.stripe)
    }

    func testManualProFlagRemainsPro() {
        let status = makeStatus(plan: .pro, lifecycle: .none)
        XCTAssertTrue(TraxProEntitlementResolver.resolve(status).isActive)
        XCTAssertEqual(TraxProEntitlementResolver.resolve(status).source, TraxProEntitlementSource.manual)
    }

    func testCreatorAccessRemainsPro() {
        let status = makeStatus(creatorAccess: true)
        XCTAssertTrue(TraxProEntitlementResolver.resolve(status).isActive)
        XCTAssertEqual(TraxProEntitlementResolver.resolve(status).source, TraxProEntitlementSource.creator)
    }

    func testFutureTrialEndRemainsProWithoutActiveStatus() {
        let status = makeStatus(trialEndsAt: future)
        XCTAssertTrue(TraxProEntitlementResolver.resolve(status).isActive)
        XCTAssertEqual(TraxProEntitlementResolver.resolve(status).source, TraxProEntitlementSource.stripe)
    }

    func testActiveAppleSubscriptionGrantsPro() {
        let status = makeStatus(
            appleSubscriptionStatus: "active",
            appleExpiresAt: future
        )
        let resolution = TraxProEntitlementResolver.resolve(status)
        XCTAssertTrue(resolution.isActive)
        XCTAssertEqual(resolution.source, TraxProEntitlementSource.apple)
    }

    func testRevokedAppleSubscriptionDoesNotGrantProWithoutOtherSources() {
        let status = makeStatus(
            appleSubscriptionStatus: "active",
            appleExpiresAt: future,
            appleRevokedAt: past
        )
        XCTAssertFalse(TraxProEntitlementResolver.resolve(status).isActive)
    }

    func testExpiredAppleSubscriptionDoesNotGrantPro() {
        let status = makeStatus(
            appleSubscriptionStatus: "expired",
            appleExpiresAt: past
        )
        XCTAssertFalse(TraxProEntitlementResolver.resolve(status).isActive)
    }

    func testStripeAndAppleTogetherRemainPro() {
        let status = makeStatus(
            lifecycle: .active,
            subscriptionStatusRaw: "active",
            appleSubscriptionStatus: "active",
            appleExpiresAt: future
        )
        let resolution = TraxProEntitlementResolver.resolve(status)
        XCTAssertTrue(resolution.isActive)
        XCTAssertEqual(resolution.source, TraxProEntitlementSource.stripe)
    }

    func testInactiveFreeUserRemainsFree() {
        let status = makeStatus()
        XCTAssertFalse(TraxProEntitlementResolver.resolve(status).isActive)
        XCTAssertEqual(TraxProEntitlementResolver.resolve(status).source, TraxProEntitlementSource.none)
    }

    private func makeStatus(
        profileID: ProfileID = SettingsFixtures.viewerID,
        plan: SubscriptionPlan = .free,
        lifecycle: SubscriptionLifecycle = .none,
        creatorAccess: Bool = false,
        subscriptionStatusRaw: String? = nil,
        trialEndsAt: Date? = nil,
        appleSubscriptionStatus: String? = nil,
        appleExpiresAt: Date? = nil,
        appleRevokedAt: Date? = nil
    ) -> BillingStatus {
        BillingStatus(
            profileID: profileID,
            plan: plan,
            lifecycle: lifecycle,
            isProEntitled: false,
            dailyTradeLimit: nil,
            dailyPostLimit: nil,
            dailyMessageLimit: nil,
            maxTradeEntryAccounts: nil,
            trialEndsAt: trialEndsAt,
            creatorAccess: creatorAccess,
            subscriptionStatusRaw: subscriptionStatusRaw,
            appleSubscriptionStatus: appleSubscriptionStatus,
            appleExpiresAt: appleExpiresAt,
            appleRevokedAt: appleRevokedAt
        )
    }
}
