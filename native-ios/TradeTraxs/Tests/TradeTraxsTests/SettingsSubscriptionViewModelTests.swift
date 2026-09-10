import XCTest
@testable import TradeTraxs

@MainActor
final class SettingsSubscriptionViewModelTests: XCTestCase {
    func testFreeUserLoadsStoreKitProducts() async {
        let products = [
            StoreKitTraxProProduct(
                id: "com.tradetraxs.traxpro.monthly",
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
        XCTAssertEqual(viewModel.subscribeButtonTitle, "Subscribe to TraxPro")
    }

    func testVerifiedPurchaseSyncsAndUnlocksPro() async {
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
        var status = SettingsFixtures.billingStatus()
        status.entitlementSource = .apple
        status.appleSubscriptionStatus = "active"
        status.appleExpiresAt = Date().addingTimeInterval(86_400 * 30)
        let viewModel = makeViewModel(
            billing: StubBilling(status: status),
            storeKit: StubStoreKit()
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        XCTAssertTrue(viewModel.showsManageSubscription)
        XCTAssertFalse(viewModel.showsApplePurchaseSection)
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

    func testFreeTierDisplayMatchesPolicy() async {
        let viewModel = makeViewModel(
            billing: StubBilling(status: freeStatus()),
            storeKit: StubStoreKit()
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }

        XCTAssertEqual(viewModel.status?.dailyTradeLimit, FreeTierPolicy.dailyTradeLimit)
        XCTAssertEqual(viewModel.status?.dailyPostLimit, FreeTierPolicy.dailyPostLimit)
        XCTAssertEqual(viewModel.status?.dailyMessageLimit, FreeTierPolicy.dailyDirectMessageLimit)
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
            dailyTradeLimit: FreeTierPolicy.dailyTradeLimit,
            dailyPostLimit: FreeTierPolicy.dailyPostLimit,
            dailyMessageLimit: FreeTierPolicy.dailyDirectMessageLimit,
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
            id: "com.tradetraxs.traxpro.monthly",
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

private struct StubStoreKit: StoreKitSubscriptionServicing {
    var products: [StoreKitTraxProProduct] = []
    var purchaseOutcome: StoreKitPurchaseOutcome = .success
    var restoreFindsEntitlement = false

    func loadProducts() async throws -> [StoreKitTraxProProduct] { products }
    func purchase(productID: String) async -> StoreKitPurchaseOutcome { purchaseOutcome }
    func restorePurchases() async throws -> Bool { restoreFindsEntitlement }
    func syncVerifiedTransactionsToServer() async throws {}
    func startTransactionListenerIfNeeded() async {}
}
