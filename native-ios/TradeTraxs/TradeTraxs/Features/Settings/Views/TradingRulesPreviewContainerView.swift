import SwiftUI

/// Full-screen TraxsPro Trading Rules preview — sample preferences, no persistence.
struct TradingRulesPreviewContainerView: View {
    let data: DataEnvironment
    let onDismiss: () -> Void

    @State private var navigationStore = NavigationStore()
    @State private var navigationCoordinator: NavigationCoordinator

    @Environment(\.dismiss) private var dismiss

    init(data: DataEnvironment, onDismiss: @escaping () -> Void) {
        self.data = data
        self.onDismiss = onDismiss
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        _navigationStore = State(initialValue: store)
        _navigationCoordinator = State(initialValue: NavigationCoordinator(store: store))
    }

    var body: some View {
        NavigationStack {
            TradingAnalyticsPreferencesView(
                data: data,
                navigationCoordinator: navigationCoordinator,
                embeddedInTraxsProRulesPreview: true
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                TraxsProPreviewSampleDataBanner(
                    unlockFeature: .premiumAnalytics,
                    onExit: exitPreview,
                    onUnlock: {
                        ExperienceHaptics.play(.selection)
                        TraxsProPreviewCoordinator.shared.noteUpgradeTappedFromPreviewBanner()
                        ProUpgradeCoordinator.shared.present(reason: .feature(.premiumAnalytics))
                    }
                )
            }
        }
        .environment(\.traxsProPreviewReadOnly, false)
        .onAppear {
            TraxsProPreviewSession.shared.beginTradingRulesPreview()
        }
        .accessibilityIdentifier("traxspro.preview.tradingRules.container")
    }

    private func exitPreview() {
        ExperienceHaptics.play(.selection)
        onDismiss()
        dismiss()
    }
}