import SwiftUI

/// Presents the shared TradeTraxsPro upgrade sheet (Settings subscription UI).
@MainActor
@Observable
final class ProUpgradeCoordinator {
    static let shared = ProUpgradeCoordinator()

    var isPresented = false
    private(set) var reason: ProGateReason?
    private(set) var retryAfterPurchase: (() -> Void)?
    private(set) var preferredTraxsProPreviewFeature: TraxsProPreviewFeature?
    private(set) var suppressTraxsProPreview = false

    func present(
        reason: ProGateReason,
        retry: (() -> Void)? = nil,
        previewFeature: TraxsProPreviewFeature? = nil,
        suppressPreview: Bool = false
    ) {
        guard ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        ) else { return }
        self.reason = reason
        self.retryAfterPurchase = retry
        preferredTraxsProPreviewFeature = previewFeature
        suppressTraxsProPreview = suppressPreview
        isPresented = true
        ProductAnalyticsCoordinator.shared.notePaywallViewed(gateReason: reason.analyticsLabel)
    }

    func resolvedPreviewFeature(for reason: ProGateReason) -> TraxsProPreviewFeature? {
        TraxsProPreviewCatalog.resolvedPreviewFeature(
            reason: reason,
            preferred: preferredTraxsProPreviewFeature,
            suppressPreview: suppressTraxsProPreview
        )
    }

    func showsPreviewProAction(for reason: ProGateReason) -> Bool {
        guard resolvedPreviewFeature(for: reason) != nil else { return false }
        return TraxsProPreviewCoordinator.shared.canPresentPreview
    }

    func presentIfNeeded(isPro: Bool, feature: ProFeatureKind, profileID: ProfileID? = nil) -> Bool {
        if ExploreModeSupport.isActive { return false }
        let verifiedPro = profileID.map { TraxProEffectiveEntitlement.hasVerifiedTraxProAccess(profileID: $0) } ?? isPro
        guard ProMonetizationPolicy.shouldGateProFeature(
            isPro: verifiedPro,
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
        preferredTraxsProPreviewFeature = nil
        suppressTraxsProPreview = false
    }

    func dismiss() {
        isPresented = false
        retryAfterPurchase = nil
        reason = nil
        preferredTraxsProPreviewFeature = nil
        suppressTraxsProPreview = false
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
            .onChange(of: coordinator.isPresented) { _, isPresented in
                if !isPresented {
                    TraxsProPreviewCoordinator.shared.paywallDidDismiss()
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

/// One-shot auto presentation of ``ProUpgradeGateSheet`` for gated home/settings routes.
@MainActor
enum ProUpgradeAutoPresent {
    static func presentFeatureGateIfNeeded(
        isRestricted: Bool,
        didPresent: inout Bool,
        feature: ProFeatureKind,
        previewFeature: TraxsProPreviewFeature? = nil,
        suppressPreview: Bool = false
    ) {
        guard isRestricted else { return }
        guard !didPresent else { return }
        guard ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        ) else { return }
        didPresent = true
        ProUpgradeCoordinator.shared.present(
            reason: .feature(feature),
            previewFeature: previewFeature,
            suppressPreview: suppressPreview
        )
    }
}
