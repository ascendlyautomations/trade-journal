import XCTest
@testable import TradeTraxs

@MainActor
final class SubscriptionComplianceTests: XCTestCase {
    func testPricingUniversalLinkIsNotRoutedInApp() throws {
        let parser = DeepLinkParser()
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/pricing"))
        XCTAssertNil(parser.parse(url: url))
        XCTAssertTrue(SubscriptionExternalLinkPolicy.shouldSuppressBrowserFallback(for: url))
    }

    func testChoosePlanDeepLinkRoutesToLogin() throws {
        let parser = DeepLinkParser()
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/choose-plan"))
        XCTAssertEqual(parser.parse(url: url), .auth(.login))
    }

    func testFinishTrialDeepLinkRoutesToLogin() throws {
        let parser = DeepLinkParser()
        let url = try XCTUnwrap(URL(string: "tradetraxs://auth/finish-trial"))
        XCTAssertEqual(parser.parse(url: url), .auth(.login))
    }

    func testFreeSubscriptionViewModelShowsInformationalCopy() async {
        let billing = SubscriptionComplianceStubBilling(
            status: BillingStatus(
                profileID: SettingsFixtures.viewerID,
                plan: .free,
                lifecycle: .none,
                isProEntitled: false,
                dailyTradeLimit: FreeTierPolicy.dailyTradeLimit,
                dailyPostLimit: FreeTierPolicy.dailyPostLimit,
                dailyMessageLimit: FreeTierPolicy.dailyDirectMessageLimit,
                maxTradeEntryAccounts: FreeTierPolicy.maxTradeEntryAccounts
            )
        )
        let viewModel = SettingsSubscriptionViewModel(
            billing: billing,
            storeKit: SubscriptionComplianceStubStoreKit(),
            session: SubscriptionComplianceStubSession(userID: SettingsFixtures.viewerID.rawValue),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        XCTAssertFalse(viewModel.showsFreePlanDetails)
        XCTAssertFalse(viewModel.showsProMembership)
        XCTAssertEqual(viewModel.planTitle, "TradeTraxs")
        XCTAssertTrue(viewModel.showsReleaseIncludedPlanDetails)
        XCTAssertTrue(viewModel.membershipSummaryFooter.localizedCaseInsensitiveContains("no additional cost"))
        XCTAssertFalse(viewModel.membershipSummaryFooter.localizedCaseInsensitiveContains("pricing"))
        XCTAssertFalse(viewModel.membershipSummaryFooter.localizedCaseInsensitiveContains("website"))
    }

    func testManualProSubscriptionViewModelShowsTraxProWithoutStripeLifecycle() async {
        let billing = SubscriptionComplianceStubBilling(
            status: BillingStatus(
                profileID: SettingsFixtures.viewerID,
                plan: .pro,
                lifecycle: .none,
                isProEntitled: false,
                dailyTradeLimit: nil,
                dailyPostLimit: nil,
                dailyMessageLimit: nil,
                maxTradeEntryAccounts: nil
            )
        )
        let viewModel = SettingsSubscriptionViewModel(
            billing: billing,
            storeKit: SubscriptionComplianceStubStoreKit(),
            session: SubscriptionComplianceStubSession(userID: SettingsFixtures.viewerID.rawValue),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        XCTAssertEqual(viewModel.planTitle, "TraxPro")
        XCTAssertTrue(viewModel.showsProMembership)
        XCTAssertFalse(viewModel.showsFreePlanDetails)
        XCTAssertEqual(
            viewModel.membershipSummaryFooter,
            "Your account has access to TraxPro features."
        )
    }

    func testProSubscriptionViewModelShowsActiveMembership() async {
        var stripeStatus = SettingsFixtures.billingStatus()
        stripeStatus.entitlementSource = .stripe
        let billing = SubscriptionComplianceStubBilling(status: stripeStatus)
        let viewModel = SettingsSubscriptionViewModel(
            billing: billing,
            storeKit: SubscriptionComplianceStubStoreKit(),
            session: SubscriptionComplianceStubSession(userID: SettingsFixtures.viewerID.rawValue),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        XCTAssertTrue(viewModel.showsProMembership)
        XCTAssertFalse(viewModel.showsFreePlanDetails)
        XCTAssertTrue(
            viewModel.membershipSummaryFooter.localizedCaseInsensitiveContains("active")
        )
        XCTAssertFalse(viewModel.showsApplePurchaseSection)
    }

    func testTraxProEntitlementPolicyMatchesWebIsProActiveBaselines() {
        let manualPro = BillingStatus(
            profileID: SettingsFixtures.viewerID,
            plan: .pro,
            lifecycle: .none,
            isProEntitled: false,
            dailyTradeLimit: nil,
            dailyPostLimit: nil,
            dailyMessageLimit: nil,
            maxTradeEntryAccounts: nil
        )
        XCTAssertTrue(manualPro.hasTraxProAccess)

        let stripePro = SettingsFixtures.billingStatus()
        XCTAssertTrue(stripePro.hasTraxProAccess)

        let free = BillingStatus(
            profileID: SettingsFixtures.viewerID,
            plan: .free,
            lifecycle: .none,
            isProEntitled: false,
            dailyTradeLimit: 10,
            dailyPostLimit: 5,
            dailyMessageLimit: 50,
            maxTradeEntryAccounts: 3
        )
        XCTAssertFalse(free.hasTraxProAccess)
    }

    func testProEntitlementSanitizerBlocksUpgradeOnWebCopy() {
        let sanitized = ProEntitlementResponseSanitizer.message(
            statusCode: 403,
            reply: "Upgrade your plan on the web to unlock it."
        )
        XCTAssertEqual(sanitized, TraxProFeatureMessaging.featureRequired)
        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("web"))
    }

    func testTraxProFeatureMessagingAvoidsExternalPurchaseSteering() {
        XCTAssertFalse(TraxProFeatureMessaging.featureRequired.localizedCaseInsensitiveContains("website"))
        XCTAssertFalse(TraxProFeatureMessaging.featureRequired.localizedCaseInsensitiveContains("pricing"))
        XCTAssertFalse(TraxProFeatureMessaging.featureRequired.localizedCaseInsensitiveContains("upgrade"))
        XCTAssertEqual(TraxProFeatureMessaging.featureRequired, "This feature requires TraxPro.")
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for condition")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private struct SubscriptionComplianceStubBilling: BillingRepository {
    let status: BillingStatus

    func status(for profileID: ProfileID) async throws -> BillingStatus {
        var copy = status
        copy.profileID = profileID
        return copy
    }

    func subscription(for profileID: ProfileID) async throws -> Subscription? { nil }

    func refreshEntitlements(for profileID: ProfileID) async throws -> BillingStatus {
        try await status(for: profileID)
    }
}

private struct SubscriptionComplianceStubStoreKit: StoreKitSubscriptionServicing {
    func loadProducts() async throws -> [StoreKitTraxProProduct] { [] }
    func purchase(productID: String) async -> StoreKitPurchaseOutcome { .userCancelled }
    func restorePurchases() async throws -> Bool { false }
    func syncVerifiedTransactionsToServer() async throws {}
    func startTransactionListenerIfNeeded() async {}
}

private struct SubscriptionComplianceStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}
