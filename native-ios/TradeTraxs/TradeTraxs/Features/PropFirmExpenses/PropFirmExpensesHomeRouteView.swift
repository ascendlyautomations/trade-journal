import SwiftUI

/// Gates Settings → Expense Tracker for TraxsPro when enforcement is on.
struct PropFirmExpensesHomeRouteView: View {
    let data: DataEnvironment

    @State private var entitlementGateRevision = 0
    @State private var didPresentUpgradeGate = false

    @Environment(\.themeColors) private var colors

    private var activeProfileID: ProfileID? {
        SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
    }

    private var showsEntitlementVerification: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldShowEntitlementVerification(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: activeProfileID
        )
    }

    private var restrictsExpenseTracker: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldRestrictPropFirmExpenseTracker(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: activeProfileID
        )
    }

    var body: some View {
        Group {
            if showsEntitlementVerification {
                TraxProEntitlementVerificationView(profileID: activeProfileID) {
                    Task { await TraxProEntitlementRefreshAction.refresh(data: data) }
                }
            } else if restrictsExpenseTracker {
                gatedContent
            } else {
                PropFirmExpensesView(data: data)
            }
        }
        .task(id: showsEntitlementVerification) {
            if showsEntitlementVerification {
                await TraxProEntitlementRefreshAction.refresh(data: data)
            }
        }
        .onAppear { presentUpgradeGateIfNeeded() }
        .onChange(of: restrictsExpenseTracker) { _, restricted in
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

    private var gatedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                TraxProFeaturePreviewCard(
                    title: "Prop Firm Expense Tracker",
                    message: "Track evaluations, funded payouts, tools, and tax-ready exports. Preview with sample data or unlock TraxsPro.",
                    feature: .propFirm,
                    accessibilityIdentifier: "propFirmExpenses.traxpro.gate"
                )
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.xs)
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Expense Tracker")
    }

    private func presentUpgradeGateIfNeeded() {
        guard restrictsExpenseTracker else { return }
        guard !didPresentUpgradeGate else { return }
        guard ProMonetizationPolicy.canPresentProPaywall(
            demoModeActive: ExploreModeSupport.isActive,
            enforcement: IosSubscriptionReleaseConfiguration.entitlementEnforcementEnabled,
            paywallEnabled: IosSubscriptionReleaseConfiguration.iosPaywallEnabled
        ) else { return }
        didPresentUpgradeGate = true
        ProUpgradeCoordinator.shared.present(reason: .feature(.propFirm))
    }
}