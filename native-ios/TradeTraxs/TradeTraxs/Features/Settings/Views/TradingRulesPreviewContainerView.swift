import SwiftUI

/// Full-screen TraxsPro Trading Rules Analytics preview, sample trades and preferences, no persistence.
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
        if let viewer = SessionBootstrapStore.shared.last.map({ ProfileID($0.data.viewer.id) }) {
            TraxsProPreviewSession.shared.beginTradingRulesPreview(
                detailCache: data.detailCache,
                viewer: viewer
            )
        }
    }

    var body: some View {
        NavigationStack(path: homePath) {
            TradingRulesComplianceHomeRouteView(
                navigationCoordinator: navigationCoordinator,
                data: data
            )
            .environment(\.tabIsActive, true)
            .safeAreaInset(edge: .top, spacing: 0) {
                TraxsProSampleDataHeader(
                    unlockFeature: .premiumAnalytics,
                    subtitle: MonetizationPlanCopy.tradingRulesPreviewSampleDataSubtitle,
                    onExit: exitPreview,
                    onUnlock: {
                        ExperienceHaptics.play(.selection)
                        TraxsProPreviewCoordinator.shared.noteUpgradeTappedFromPreviewBanner()
                        ProUpgradeCoordinator.shared.present(reason: .feature(.premiumAnalytics))
                    }
                )
            }
            .navigationDestination(for: HomeRoute.self) { route in
                previewDestination(for: route)
            }
        }
        .environment(\.traxsProPreviewReadOnly, true)
        .onAppear {
            navigationStore.sessionPhase = .authenticated
        }
        .accessibilityIdentifier("traxspro.preview.tradingRules.container")
    }

    private var homePath: Binding<[HomeRoute]> {
        Binding(
            get: { navigationStore.paths.home },
            set: { navigationStore.paths.home = $0 }
        )
    }

    private func exitPreview() {
        ExperienceHaptics.play(.selection)
        onDismiss()
        dismiss()
    }

    @ViewBuilder
    private func previewDestination(for route: HomeRoute) -> some View {
        switch route {
        case .tradeDetail(let tradeID):
            if TraxsProPreviewSupport.allowsJournalTradeNavigation(tradeID: tradeID) {
                JournalTradeDetailView(
                    tradeID: tradeID,
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            } else {
                previewUnavailable(message: "This preview only includes sample journal trades.")
            }
        case .tradingRulesRuleDetail(let ruleIDRaw):
            TradingRulesRuleDetailView(
                ruleIDRaw: ruleIDRaw,
                navigationCoordinator: navigationCoordinator,
                detailCache: data.detailCache
            )
        case .tradingRulesDayDetail(let dayKey):
            TradingRulesDayDetailView(
                dayKey: dayKey,
                navigationCoordinator: navigationCoordinator,
                detailCache: data.detailCache
            )
        case .tradingRulesTrends:
            TradingRulesComplianceTrendsView()
        case .tradingRulesViolationHistory:
            TradingRulesViolationHistoryGroupsView(
                navigationCoordinator: navigationCoordinator,
                detailCache: data.detailCache
            )
        default:
            previewUnavailable(message: "Exit preview to use other parts of the app.")
        }
    }

    private func previewUnavailable(message: String) -> some View {
        ExperienceEmptyState(
            icon: .chart,
            title: "Unavailable in preview",
            message: message
        )
    }
}