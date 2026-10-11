import XCTest
@testable import TradeTraxs

@MainActor
final class SettingsSubscriptionViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SessionBillingEntitlementStore.shared.clear()
        MonetizationRuntimeConfiguration.shared.resetToFailClosed()
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = false
    }

    override func tearDown() {
        SessionBillingEntitlementStore.shared.clear()
        MonetizationRuntimeConfiguration.shared.resetToFailClosed()
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = false
        super.tearDown()
    }

    func testFreeUserLoadsStoreKitProducts() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let products = [
            StoreKitTraxProProduct(
                id: "com.tradetraxs.traxspro.monthly",
                displayName: "TraxPro Monthly",
                displayPrice: "$23.99",
                subscriptionPeriodLabel: "Monthly",
                billingInterval: .monthly,
                hasEligibleIntroductoryOffer: false
            ),
        ]
        let viewModel = makeViewModel(
            billing: StubBilling(status: freeStatus()),
            storeKit: StubStoreKit(products: products)
        )
        viewModel.loadIfNeeded()
        await waitFor { if case .loaded = viewModel.productsState { return true }; return false }

        if case .loaded(let loaded) = viewModel.productsState {
            XCTAssertEqual(loaded.count, 1)
            XCTAssertEqual(loaded.first?.displayPrice, "$23.99")
        } else {
            XCTFail("Expected loaded products")
        }
        XCTAssertTrue(viewModel.showsApplePurchaseSection)
        XCTAssertEqual(viewModel.subscribeButtonTitle, "Upgrade to Pro")
    }

    func testVerifiedPurchaseSyncsAndUnlocksPro() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let storeKit = StubStoreKit(
            products: [sampleProduct()],
            purchaseOutcome: .success
        )
        let billing = MutableBillingRepository(initial: freeStatus())
        billing.upgradeEntitlementOnRefreshNumber = 2
        let viewModel = makeViewModel(billing: billing, storeKit: storeKit)

        viewModel.loadIfNeeded()
        await waitFor { viewModel.selectedProduct != nil }
        XCTAssertFalse(viewModel.status?.hasTraxProAccess == true)
        await viewModel.purchaseSelectedPlan()
        await waitFor { viewModel.status?.hasTraxProAccess == true }

        XCTAssertTrue(viewModel.showsProMembership)
        XCTAssertFalse(viewModel.showsApplePurchaseSection)
        XCTAssertEqual(billing.refreshCount, 2)
    }

    func testCancelledPurchaseStaysFree() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let viewModel = makeViewModel(
            billing: StubBilling(status: freeStatus()),
            storeKit: StubStoreKit(products: [sampleProduct()], purchaseOutcome: .userCancelled)
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.selectedProduct != nil }
        await viewModel.purchaseSelectedPlan()

        XCTAssertFalse(viewModel.showsProMembership)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUnverifiedPurchaseNeverUnlocks() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let billing = MutableBillingRepository(initial: freeStatus())
        let viewModel = makeViewModel(
            billing: billing,
            storeKit: StubStoreKit(products: [sampleProduct()], purchaseOutcome: .unverified)
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.selectedProduct != nil }
        await viewModel.purchaseSelectedPlan()

        XCTAssertFalse(viewModel.status?.hasTraxProAccess == true)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testStripeProDoesNotShowAppleSubscribeCTA() async {
        var status = SettingsFixtures.billingStatus()
        status.entitlementSource = .stripe
        let viewModel = makeViewModel(
            billing: StubBilling(status: status),
            storeKit: StubStoreKit(products: [sampleProduct()])
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        XCTAssertTrue(viewModel.showsProMembership)
        XCTAssertFalse(viewModel.showsApplePurchaseSection)
        XCTAssertTrue(viewModel.membershipSummaryFooter.localizedCaseInsensitiveContains("outside the app store"))
    }

    func testAppleProShowsManageSubscription() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        var status = SettingsFixtures.billingStatus()
        status.entitlementSource = .apple
        status.appleSubscriptionStatus = "active"
        status.appleExpiresAt = Date().addingTimeInterval(86_400 * 30)
        status.appleProductID = "com.tradetraxs.traxspro.monthly"
        status.billingInterval = .monthly
        let viewModel = makeViewModel(
            billing: StubBilling(status: status),
            storeKit: StubStoreKit(products: [sampleProduct()])
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }
        await waitFor { viewModel.activePlanStoreKitPrice != nil }

        XCTAssertTrue(viewModel.showsManageSubscription)
        XCTAssertFalse(viewModel.showsApplePurchaseSection)
        XCTAssertEqual(viewModel.activePlanStoreKitPrice, "$23.99")
        XCTAssertEqual(viewModel.activePlanBillingIntervalLabel, "Monthly")
        XCTAssertTrue(viewModel.renewalDetail?.hasPrefix("Renews") == true)
    }

    func testAppleProCancelAtPeriodEndUsesExpiresCopy() {
        var status = SettingsFixtures.billingStatus()
        status.entitlementSource = .apple
        status.appleExpiresAt = Date().addingTimeInterval(86_400 * 30)
        status.cancelAtPeriodEnd = true
        let detail = SubscriptionPresentationPolicy.renewalDetail(for: status)
        XCTAssertEqual(detail?.hasPrefix("Expires"), true)
    }

    func testAppleProLoadsStoreKitProductsWhenEntitled() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        var status = SettingsFixtures.billingStatus()
        status.entitlementSource = .apple
        status.appleProductID = "com.tradetraxs.traxspro.monthly"
        let storeKit = StubStoreKit(products: [sampleProduct()])
        let viewModel = makeViewModel(billing: StubBilling(status: status), storeKit: storeKit)
        viewModel.loadIfNeeded()
        await waitFor { if case .loaded = viewModel.productsState { return true }; return false }
        XCTAssertTrue(viewModel.shouldLoadStoreKitProductsForDisplay)
    }

    func testRedeemOfferCodeInvokesStoreKitRedemptionPath() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let metrics = StoreKitStubMetrics()
        let viewModel = makeViewModel(
            billing: StubBilling(status: freeStatus()),
            storeKit: StubStoreKit(metrics: metrics)
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        await viewModel.redeemOfferCode()

        XCTAssertTrue(metrics.offerCodeRedemptionPresented)
        XCTAssertTrue(metrics.listenerStarted)
        XCTAssertGreaterThanOrEqual(metrics.syncVerifiedCalls, 1)
    }

    func testRedeemOfferCodeDismissWithoutEntitlementDoesNotGrantPro() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let viewModel = makeViewModel(
            billing: StubBilling(status: freeStatus()),
            storeKit: StubStoreKit(metrics: StoreKitStubMetrics())
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        await viewModel.redeemOfferCode()

        XCTAssertFalse(viewModel.showsProMembership)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.actionMessage)
    }

    func testRedeemOfferCodeSyncsEntitlementsAfterRedemptionSheet() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let billing = MutableBillingRepository(initial: freeStatus())
        let metrics = StoreKitStubMetrics()
        let viewModel = makeViewModel(
            billing: billing,
            storeKit: StubStoreKit(metrics: metrics)
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }
        billing.nextStatus = proBilling(source: .apple)

        await viewModel.redeemOfferCode()

        XCTAssertTrue(metrics.offerCodeRedemptionPresented)
        XCTAssertGreaterThanOrEqual(metrics.syncVerifiedCalls, 1)
        XCTAssertGreaterThanOrEqual(billing.refreshCount, 1)
        XCTAssertTrue(viewModel.showsProMembership)
    }

    func testRedeemOfferCodeServerSyncFailureDoesNotGrantPro() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let metrics = StoreKitStubMetrics()
        metrics.syncVerifiedShouldFail = true
        let viewModel = makeViewModel(
            billing: StubBilling(status: freeStatus()),
            storeKit: StubStoreKit(metrics: metrics)
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        await viewModel.redeemOfferCode()

        XCTAssertFalse(viewModel.showsProMembership)
    }

    func testGrantedProShowsActiveWithoutPurchaseCTA() async {
        var status = SettingsFixtures.billingStatus()
        status.plan = .pro
        status.entitlementSource = .creator
        let viewModel = makeViewModel(
            billing: StubBilling(status: status),
            storeKit: StubStoreKit(products: [sampleProduct()])
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        XCTAssertTrue(viewModel.showsProMembership)
        XCTAssertFalse(viewModel.showsApplePurchaseSection)
    }

    func testRestoreWithVerifiedEntitlementUnlocksPro() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let billing = MutableBillingRepository(initial: freeStatus())
        let viewModel = makeViewModel(
            billing: billing,
            storeKit: StubStoreKit(restoreFindsEntitlement: true)
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }
        billing.nextStatus = proBilling(source: .apple)

        await viewModel.restorePurchases()
        await waitFor { viewModel.status?.hasTraxProAccess == true }
        XCTAssertTrue(viewModel.showsProMembership)
    }

    func testPurchaseSendsAuthenticatedUserAsAppAccountToken() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let user = UUID()
        let capture = PurchaseCapture()
        let storeKit = StubStoreKit(products: [sampleProduct()], capture: capture)
        let viewModel = SettingsSubscriptionViewModel(
            billing: StubBilling(
                status: BillingStatus(
                    profileID: ProfileID(user.uuidString),
                    plan: .free,
                    lifecycle: .none,
                    isProEntitled: false
                )
            ),
            storeKit: storeKit,
            session: SubscriptionTestSession(userID: user.uuidString),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        await waitFor { if case .loaded = viewModel.productsState { return true }; return false }
        await viewModel.purchaseSelectedPlan()
        XCTAssertEqual(capture.appAccountToken, user)
    }

    func testRetryAfterEntitlementFailureLoadsStoreKitProducts() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let userID = UUID().uuidString
        var status = freeStatus()
        status.profileID = ProfileID(userID)
        let billing = FailThenSucceedBilling(status: status, failures: 1)
        let metrics = StoreKitStubMetrics()
        let viewModel = SettingsSubscriptionViewModel(
            billing: billing,
            storeKit: StubStoreKit(products: [sampleProduct()], metrics: metrics),
            session: SubscriptionTestSession(userID: userID),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.errorMessage != nil }

        XCTAssertNil(viewModel.status)
        XCTAssertEqual(viewModel.planTitle, "—")
        XCTAssertEqual(viewModel.errorMessage, "Please try again.")
        XCTAssertEqual(metrics.loadCount, 0)
        XCTAssertFalse(viewModel.showsApplePurchaseSection)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.planTitle, "Free")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(metrics.loadCount, 1)
        XCTAssertTrue(viewModel.showsApplePurchaseSection)
        if case .loaded(let products) = viewModel.productsState {
            XCTAssertEqual(products.map(\.id), ["com.tradetraxs.traxspro.monthly"])
        } else {
            XCTFail("Expected StoreKit products after entitlement recovery")
        }
    }

    func testForegroundEntitlementRecoveryLoadsStoreKitProducts() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let userID = UUID().uuidString
        var status = freeStatus()
        status.profileID = ProfileID(userID)
        let metrics = StoreKitStubMetrics()
        let viewModel = SettingsSubscriptionViewModel(
            billing: FailThenSucceedBilling(status: status, failures: 1),
            storeKit: StubStoreKit(products: [sampleProduct()], metrics: metrics),
            session: SubscriptionTestSession(userID: userID),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.errorMessage != nil }

        XCTAssertNil(viewModel.status)
        XCTAssertEqual(viewModel.planTitle, "—")
        XCTAssertEqual(metrics.loadCount, 0)

        viewModel.applyForegroundEntitlementRefresh(status)
        await waitFor { metrics.loadCount == 1 }

        XCTAssertEqual(viewModel.planTitle, "Free")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.showsApplePurchaseSection)
        XCTAssertTrue(viewModel.showsRestorePurchases)
        if case .loaded(let products) = viewModel.productsState {
            XCTAssertEqual(products.map(\.id), ["com.tradetraxs.traxspro.monthly"])
        } else {
            XCTFail("Expected StoreKit products after a foreground entitlement update")
        }
    }

    func testFailedStoreKitLoadRetriesOnNextEntitlementRefresh() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let metrics = StoreKitStubMetrics()
        metrics.productLoadFailuresRemaining = 1
        let viewModel = makeViewModel(
            billing: StubBilling(status: freeStatus()),
            storeKit: StubStoreKit(products: [sampleProduct()], metrics: metrics)
        )

        viewModel.loadIfNeeded()
        await waitFor {
            if case .failed = viewModel.productsState { return true }
            return false
        }
        XCTAssertEqual(viewModel.planTitle, "Free")
        XCTAssertEqual(metrics.loadCount, 1)

        await viewModel.refresh()

        XCTAssertEqual(metrics.loadCount, 2)
        if case .loaded = viewModel.productsState {
        } else {
            XCTFail("Expected a later refresh to load StoreKit products")
        }
    }

    func testFreeTierDisplayMatchesPolicy() async {
        IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled = true
        let viewModel = makeViewModel(
            billing: StubBilling(status: freeStatus()),
            storeKit: StubStoreKit()
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        XCTAssertNil(viewModel.status?.dailyTradeLimit)
        XCTAssertNil(viewModel.status?.dailyPostLimit)
        XCTAssertNil(viewModel.status?.dailyMessageLimit)
        XCTAssertEqual(viewModel.status?.maxTradeEntryAccounts, FreeTierPolicy.maxTradeEntryAccounts)
    }

    private func makeViewModel(
        billing: any BillingRepository,
        storeKit: StubStoreKit
    ) -> SettingsSubscriptionViewModel {
        SettingsSubscriptionViewModel(
            billing: billing,
            storeKit: storeKit,
            session: SubscriptionTestSession(userID: SettingsFixtures.viewerID.rawValue),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
    }

    private func freeStatus() -> BillingStatus {
        BillingStatus(
            profileID: SettingsFixtures.viewerID,
            plan: .free,
            lifecycle: .none,
            isProEntitled: false,
            dailyTradeLimit: nil,
            dailyPostLimit: nil,
            dailyMessageLimit: nil,
            maxTradeEntryAccounts: FreeTierPolicy.maxTradeEntryAccounts
        )
    }

    private func proBilling(source: TraxProEntitlementSource) -> BillingStatus {
        var status = SettingsFixtures.billingStatus()
        status.entitlementSource = source
        return status
    }

    private func sampleProduct() -> StoreKitTraxProProduct {
        StoreKitTraxProProduct(
            id: "com.tradetraxs.traxspro.monthly",
            displayName: "TraxPro Monthly",
            displayPrice: "$23.99",
            subscriptionPeriodLabel: "Monthly",
            billingInterval: .monthly,
            hasEligibleIntroductoryOffer: false
        )
    }

    private func waitFor(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private struct SubscriptionTestSession: SessionProviding {
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

private struct StubBilling: BillingRepository {
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

private final class FailThenSucceedBilling: BillingRepository, @unchecked Sendable {
    let status: BillingStatus
    private var failuresRemaining: Int

    init(status: BillingStatus, failures: Int) {
        self.status = status
        self.failuresRemaining = failures
    }

    func status(for profileID: ProfileID) async throws -> BillingStatus {
        var copy = status
        copy.profileID = profileID
        return copy
    }

    func subscription(for profileID: ProfileID) async throws -> Subscription? { nil }

    func refreshEntitlements(for profileID: ProfileID) async throws -> BillingStatus {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw AppError.transport(.server(statusCode: 500, message: "{\"error\":\"Could not load profile\"}"))
        }
        var copy = status
        copy.profileID = profileID
        return copy
    }
}

private final class MutableBillingRepository: BillingRepository, @unchecked Sendable {
    private var current: BillingStatus
    var nextStatus: BillingStatus?
    /// When set, upgrades to TraxPro only once ``refreshCount`` reaches this value (initial load stays Free).
    var upgradeEntitlementOnRefreshNumber: Int?
    private(set) var refreshCount = 0

    init(initial: BillingStatus) {
        current = initial
    }

    func status(for profileID: ProfileID) async throws -> BillingStatus {
        var copy = current
        copy.profileID = profileID
        return copy
    }

    func subscription(for profileID: ProfileID) async throws -> Subscription? { nil }

    func refreshEntitlements(for profileID: ProfileID) async throws -> BillingStatus {
        refreshCount += 1
        if let nextStatus {
            current = nextStatus
        } else if upgradeEntitlementOnRefreshNumber.map({ refreshCount >= $0 }) == true {
            current.plan = .pro
            current.entitlementSource = .apple
            current.appleSubscriptionStatus = "active"
            current.appleExpiresAt = Date().addingTimeInterval(86_400 * 30)
        }
        var copy = current
        copy.profileID = profileID
        return copy
    }
}

final class PurchaseCapture: @unchecked Sendable {
    var appAccountToken: UUID?
}

final class StoreKitStubMetrics: @unchecked Sendable {
    var offerCodeRedemptionPresented = false
    var syncVerifiedCalls = 0
    var listenerStarted = false
    var syncVerifiedShouldFail = false
    var loadCount = 0
    var productLoadFailuresRemaining = 0
}

private struct StubStoreKit: StoreKitSubscriptionServicing {
    var products: [StoreKitTraxProProduct] = []
    var purchaseOutcome: StoreKitPurchaseOutcome = .success
    var restoreFindsEntitlement = false
    var capture: PurchaseCapture? = nil
    var metrics: StoreKitStubMetrics? = nil
    var offerCodeRedemptionError: Error? = nil

    func loadProducts() async throws -> [StoreKitTraxProProduct] {
        metrics?.loadCount += 1
        if let metrics, metrics.productLoadFailuresRemaining > 0 {
            metrics.productLoadFailuresRemaining -= 1
            throw URLError(.cannotConnectToHost)
        }
        return products
    }
    func purchase(productID: String, appAccountToken: UUID?) async -> StoreKitPurchaseOutcome {
        capture?.appAccountToken = appAccountToken
        return purchaseOutcome
    }
    func restorePurchases() async throws -> Bool { restoreFindsEntitlement }
    func syncVerifiedTransactionsToServer() async throws {
        metrics?.syncVerifiedCalls += 1
        if metrics?.syncVerifiedShouldFail == true {
            throw AppError.unknown(message: "sync failed")
        }
    }
    func startTransactionListenerIfNeeded() async {
        metrics?.listenerStarted = true
    }
    func presentOfferCodeRedemption() async throws {
        metrics?.offerCodeRedemptionPresented = true
        if let offerCodeRedemptionError {
            throw offerCodeRedemptionError
        }
    }
}
