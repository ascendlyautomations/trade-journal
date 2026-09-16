import Foundation
import Observation
import StoreKit
import UIKit

enum SettingsSubscriptionProductsState: Equatable {
    case idle
    case loading
    case loaded([StoreKitTraxProProduct])
    case failed
}

enum SettingsSubscriptionActionState: Equatable {
    case idle
    case purchasing
    case synchronizing
    case restoring
    case pendingApproval
}

@Observable
@MainActor
final class SettingsSubscriptionViewModel {
    private let billing: any BillingRepository
    private let storeKit: any StoreKitSubscriptionServicing
    private let session: any SessionProviding
    private let navigationCoordinator: NavigationCoordinator

    private(set) var status: BillingStatus?
    private(set) var productsState: SettingsSubscriptionProductsState = .idle
    private(set) var actionState: SettingsSubscriptionActionState = .idle
    private(set) var isLoading = false
    private(set) var isRefreshingEntitlements = false
    private(set) var errorMessage: String?
    private(set) var actionMessage: String?
    var selectedProductID: String?

    private var hasLoaded = false
    private var purchaseInFlight = false

    init(
        billing: any BillingRepository,
        storeKit: any StoreKitSubscriptionServicing,
        session: any SessionProviding,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.billing = billing
        self.storeKit = storeKit
        self.session = session
        self.navigationCoordinator = navigationCoordinator
    }

    var planTitle: String {
        guard let status else { return "—" }
        if !IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled {
            return status.hasTraxProAccess ? "TraxPro" : "TradeTraxs"
        }
        return status.hasTraxProAccess ? "TraxPro" : "Free"
    }

    var showsReleaseIncludedPlanDetails: Bool {
        !IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled
            && status?.hasTraxProAccess != true
    }

    var showsProMembership: Bool {
        status?.hasTraxProAccess == true
    }

    var showsFreePlanDetails: Bool {
        SubscriptionPresentationPolicy.showsApplePurchaseOptions(for: status)
    }

    var showsApplePurchaseSection: Bool {
        showsFreePlanDetails && actionState != .pendingApproval
    }

    var showsRestorePurchases: Bool {
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else { return false }
        return showsFreePlanDetails || status?.entitlementSource == .apple
    }

    var showsManageSubscription: Bool {
        SubscriptionPresentationPolicy.showsAppleManageSubscription(for: status)
    }

    var membershipSummaryFooter: String {
        guard let status else {
            return "Your plan details appear here when you're signed in."
        }
        return SubscriptionPresentationPolicy.activeSummary(for: status)
    }

    var billingDetail: String? {
        guard let status else { return nil }
        return SubscriptionPresentationPolicy.billingDetail(for: status)
    }

    var renewalDetail: String? {
        guard let status else { return nil }
        return SubscriptionPresentationPolicy.renewalDetail(for: status)
    }

    var selectedProduct: StoreKitTraxProProduct? {
        guard case .loaded(let products) = productsState else { return nil }
        if let selectedProductID,
           let match = products.first(where: { $0.id == selectedProductID }) {
            return match
        }
        return products.first
    }

    var subscribeButtonTitle: String {
        guard let product = selectedProduct else { return "Subscribe" }
        if product.hasEligibleIntroductoryOffer {
            return "Start TraxPro"
        }
        return "Subscribe to TraxPro"
    }

    var isPrimaryActionDisabled: Bool {
        purchaseInFlight
            || actionState == .purchasing
            || actionState == .synchronizing
            || actionState == .restoring
            || selectedProduct == nil
            || productsState == .loading
    }

    let traxProFeatureHighlights: [String] = [
        "Trade AI analysis on your trades",
        "Higher daily trade, post, and message limits",
        "More active trading accounts",
        "Advanced psychology and analytics tools",
    ]

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let cached = SessionBillingEntitlementStore.shared.status {
            status = cached
        }
        Task { await refreshAll(reloadProducts: true) }
    }

    func applyForegroundEntitlementRefresh(_ refreshed: BillingStatus) {
        status = refreshed
        errorMessage = nil
    }

    func refresh() async {
        await refreshAll(reloadProducts: showsFreePlanDetails)
    }

    func retryLoadProducts() {
        Task { await loadProductsIfNeeded(force: true) }
    }

    func selectProduct(_ productID: String) {
        selectedProductID = productID
    }

    func purchaseSelectedPlan() async {
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else { return }
        guard !purchaseInFlight else { return }
        guard let product = selectedProduct else {
            errorMessage = "Choose a TraxPro plan to continue."
            return
        }

        purchaseInFlight = true
        actionState = .purchasing
        actionMessage = nil
        errorMessage = nil

        let outcome = await storeKit.purchase(productID: product.id)
        switch outcome {
        case .success:
            actionState = .synchronizing
            actionMessage = "Confirming your TraxPro access…"
            await reconcileEntitlements()
            if status?.hasTraxProAccess == true {
                actionMessage = "TraxPro is now active on your account."
                errorMessage = nil
            } else {
                errorMessage = "Purchase received. TraxPro will unlock once verification completes."
            }
        case .userCancelled:
            actionMessage = nil
        case .pending:
            actionState = .pendingApproval
            actionMessage = "Your purchase is pending approval."
        case .unverified:
            errorMessage = "We couldn't verify that purchase. TraxPro was not unlocked."
        case .failed(let message):
            errorMessage = ProEntitlementResponseSanitizer.sanitizedOrNeutral(message)
        }

        actionState = actionState == .pendingApproval ? .pendingApproval : .idle
        purchaseInFlight = false
    }

    func restorePurchases() async {
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else { return }
        guard actionState == .idle else { return }
        actionState = .restoring
        actionMessage = "Restoring purchases…"
        errorMessage = nil

        do {
            let restored = try await storeKit.restorePurchases()
            actionState = .synchronizing
            await reconcileEntitlements()
            if status?.hasTraxProAccess == true {
                actionMessage = "TraxPro access restored."
            } else if restored {
                actionMessage = "Purchase found. TraxPro will unlock once verification completes."
            } else {
                actionMessage = "No App Store subscription was found for this Apple ID."
            }
        } catch {
            errorMessage = "Couldn't restore purchases. Check your connection and try again."
            actionMessage = nil
        }

        actionState = .idle
    }

    func manageSubscription() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else {
            errorMessage = "Subscription management is unavailable right now."
            return
        }

        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            errorMessage = "Couldn't open subscription management."
        }
    }

    func openSubscriptionFromUpgradeSheet() {
        navigationCoordinator.open(.settingsStack([.home, .subscription]))
    }

    private func refreshAll(reloadProducts: Bool) async {
        let blocking = status == nil
        if blocking {
            isLoading = true
        } else {
            isRefreshingEntitlements = true
        }
        defer {
            isLoading = false
            isRefreshingEntitlements = false
        }

        guard let userID = await session.currentUserID else {
            errorMessage = "Sign in to view your plan."
            return
        }

        await reconcileEntitlements(profileID: ProfileID(userID.rawValue))
        if IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled,
           reloadProducts, showsFreePlanDetails
        {
            await loadProductsIfNeeded(force: false)
        }
    }

    private func reconcileEntitlements(profileID: ProfileID? = nil) async {
        guard let userID = await session.currentUserID else { return }
        let profile = profileID ?? ProfileID(userID.rawValue)

        do {
            if IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled {
                try? await storeKit.syncVerifiedTransactionsToServer()
            }
            let refreshed = try await billing.refreshEntitlements(for: profile)
            status = refreshed
            SessionBillingEntitlementStore.shared.apply(refreshed)
            errorMessage = nil
        } catch {
            if userID.rawValue.hasPrefix("dev.") {
                status = BillingStatus(
                    profileID: profile,
                    plan: .free,
                    lifecycle: .none,
                    isProEntitled: false,
                    dailyTradeLimit: FreeTierPolicy.dailyTradeLimit,
                    dailyPostLimit: FreeTierPolicy.dailyPostLimit,
                    dailyMessageLimit: FreeTierPolicy.dailyDirectMessageLimit,
                    maxTradeEntryAccounts: FreeTierPolicy.maxTradeEntryAccounts
                )
                errorMessage = nil
            } else if status == nil {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    private func loadProductsIfNeeded(force: Bool) async {
        guard IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled else {
            productsState = .idle
            return
        }
        if !force, case .loaded = productsState { return }
        productsState = .loading
        do {
            let products = try await storeKit.loadProducts()
            productsState = products.isEmpty ? .failed : .loaded(products)
            if selectedProductID == nil {
                selectedProductID = products.first?.id
            }
        } catch {
            productsState = .failed
        }
    }
}
