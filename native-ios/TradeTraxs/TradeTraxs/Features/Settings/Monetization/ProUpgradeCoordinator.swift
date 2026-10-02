import SwiftUI

/// Presents the shared TradeTraxs Pro upgrade sheet (Settings subscription UI).
@MainActor
@Observable
final class ProUpgradeCoordinator {
    static let shared = ProUpgradeCoordinator()

    var isPresented = false
    private(set) var reason: ProGateReason?
    private(set) var retryAfterPurchase: (() -> Void)?

    func present(reason: ProGateReason, retry: (() -> Void)? = nil) {
        guard ProMonetizationPolicy.canPresentProPaywall(
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        ) else { return }
        self.reason = reason
        self.retryAfterPurchase = retry
        isPresented = true
    }

    func presentIfNeeded(isPro: Bool, feature: ProFeatureKind) -> Bool {
        guard ProMonetizationPolicy.shouldGateProFeature(
            isPro: isPro,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled
        ) else { return false }
        present(reason: .feature(feature))
        return true
    }

    @discardableResult
    func presentIfNeeded(fromError error: Error) -> Bool {
        ProLimitPresentation.presentUpgradeIfProGate(error)
    }

    func dismissAfterConfirmedPro(onConfirmed: @escaping () -> Void) {
        retryAfterPurchase = onConfirmed
    }

    func completePurchaseIfPro(active: Bool) {
        guard active else { return }
        isPresented = false
        retryAfterPurchase?()
        retryAfterPurchase = nil
        reason = nil
    }

    func dismiss() {
        isPresented = false
        retryAfterPurchase = nil
        reason = nil
    }
}

struct ProUpgradeSheetModifier: ViewModifier {
    @Bindable var coordinator: ProUpgradeCoordinator
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.navigationEnvironment) private var navigationEnvironment

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $coordinator.isPresented) {
                if let reason = coordinator.reason {
                    ProUpgradeGateSheet(
                        reason: reason,
                        coordinator: coordinator,
                        data: appEnvironment.data,
                        navigationCoordinator: navigationEnvironment.coordinator
                    )
                } else {
                    NavigationStack {
                        SettingsSubscriptionView(
                            data: appEnvironment.data,
                            navigationCoordinator: navigationEnvironment.coordinator
                        )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { coordinator.dismiss() }
                            }
                        }
                    }
                }
            }
    }
}

extension View {
    @MainActor
    func proUpgradeSheet(coordinator: ProUpgradeCoordinator) -> some View {
        modifier(ProUpgradeSheetModifier(coordinator: coordinator))
    }

    @MainActor
    func proUpgradeSheet() -> some View {
        proUpgradeSheet(coordinator: .shared)
    }
}
