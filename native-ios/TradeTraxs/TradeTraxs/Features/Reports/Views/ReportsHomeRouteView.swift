import SwiftUI

/// Gates Home → Reports, auto-presents the shared TraxsPro upgrade sheet for verified Free users.
struct ReportsHomeRouteView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    @State private var entitlementGateRevision = 0
    @State private var didPresentUpgradeGate = false

    private var reportsViewerProfileID: ProfileID? {
        SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
    }

    private var showsEntitlementVerification: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldShowEntitlementVerification(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: reportsViewerProfileID
        )
    }

    /// Paywall gating only — same stable restriction semantics as ``PropFirmExpensesHomeRouteView``
    /// (preview session does not flip this to unrestricted).
    private var restrictsTradingReportsCatalog: Bool {
        _ = entitlementGateRevision
        return TraxProEffectiveEntitlement.shouldRestrictPremiumFeatures(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: reportsViewerProfileID
        )
    }

    var body: some View {
        ReportsScreenView(
            data: data,
            navigationCoordinator: navigationCoordinator
        )
        .onAppear { presentUpgradeGateIfNeeded() }
        .onChange(of: restrictsTradingReportsCatalog) { _, restricted in
            if restricted {
                presentUpgradeGateIfNeeded()
            } else {
                didPresentUpgradeGate = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
    }

    private func presentUpgradeGateIfNeeded() {
        guard !showsEntitlementVerification else { return }
        ProUpgradeAutoPresent.presentFeatureGateIfNeeded(
            isRestricted: restrictsTradingReportsCatalog,
            didPresent: &didPresentUpgradeGate,
            feature: .tradingReports
        )
    }
}