import SwiftUI

/// Isolated navigation stack for signed-in Free users exploring Backtest Lab with sample data.
struct BacktestLabPreviewContainerView: View {
    let productionData: DataEnvironment
    let onDismiss: () -> Void

    @State private var navigationStore = NavigationStore()
    @State private var navigationCoordinator: NavigationCoordinator

    @Environment(\.dismiss) private var dismiss

    private var previewData: DataEnvironment {
        TraxsProPreviewSession.shared.activePreviewEnvironment?.data ?? productionData
    }

    init(productionData: DataEnvironment, onDismiss: @escaping () -> Void) {
        self.productionData = productionData
        self.onDismiss = onDismiss
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        _navigationStore = State(initialValue: store)
        _navigationCoordinator = State(initialValue: NavigationCoordinator(store: store))
        if let viewer = SessionBootstrapStore.shared.last.map({ ProfileID($0.data.viewer.id) }) {
            TraxsProPreviewSession.shared.beginBacktestLabPreview(
                production: productionData,
                viewer: viewer
            )
        }
    }

    var body: some View {
        NavigationStack(path: homePath) {
            BacktestLabView(
                data: previewData,
                navigationCoordinator: navigationCoordinator,
                embeddedInTraxsProPreview: true
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                TraxsProSampleDataHeader(
                    unlockFeature: .backtestLab,
                    subtitle: MonetizationPlanCopy.backtestLabPreviewSampleDataSubtitle,
                    onExit: exitPreview,
                    onUnlock: {
                        ExperienceHaptics.play(.selection)
                        TraxsProPreviewCoordinator.shared.noteUpgradeTappedFromPreviewBanner()
                        ProUpgradeCoordinator.shared.present(reason: .feature(.backtestLab))
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
        .accessibilityIdentifier("traxspro.preview.backtestLab.container")
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
        case .backtestCalendar:
            BacktestCalendarView(
                data: previewData,
                navigationCoordinator: navigationCoordinator,
                embeddedInTraxsProPreview: true
            )
        case .backtestTradingDay(let dayKey):
            BacktestTradingDayDetailView(
                dayKey: dayKey,
                data: previewData,
                navigationCoordinator: navigationCoordinator,
                embeddedInTraxsProPreview: true
            )
        case .tradeDetail(let tradeID):
            if TraxsProPreviewSupport.allowsJournalTradeNavigation(tradeID: tradeID) {
                JournalTradeDetailView(
                    tradeID: tradeID,
                    data: previewData,
                    navigationCoordinator: navigationCoordinator
                )
            } else {
                previewUnavailable(message: "This preview only includes sample backtest trades.")
            }
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