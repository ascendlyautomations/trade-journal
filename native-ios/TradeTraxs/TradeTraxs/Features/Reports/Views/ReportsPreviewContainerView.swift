import SwiftUI

/// Isolated navigation stack for signed-in Free users exploring Reports with sample data.
struct ReportsPreviewContainerView: View {
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
        NavigationStack(path: homePath) {
            ReportsScreenView(
                data: data,
                navigationCoordinator: navigationCoordinator,
                embeddedInTraxsProPreview: true
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                TraxsProSampleDataHeader(
                    unlockFeature: .tradingReports,
                    subtitle: MonetizationPlanCopy.reportsPreviewSampleDataSubtitle,
                    onExit: exitPreview,
                    onUnlock: {
                        ExperienceHaptics.play(.selection)
                        TraxsProPreviewCoordinator.shared.noteUpgradeTappedFromPreviewBanner()
                        ProUpgradeCoordinator.shared.present(reason: .feature(.tradingReports))
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
            let viewer = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
            TraxsProPreviewSession.shared.beginReportsPreview(
                detailCache: data.detailCache,
                viewer: viewer
            )
        }
        .accessibilityIdentifier("traxspro.preview.reports.container")
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
        case .report(let reportID):
            ReportsPreviewReportDetailRouteView(
                reportID: reportID,
                data: data,
                navigationCoordinator: navigationCoordinator
            )
        case .tradeDetail(let tradeID):
            if TraxsProPreviewSupport.allowsJournalTradeNavigation(tradeID: tradeID) {
                JournalTradeDetailView(
                    tradeID: tradeID,
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            } else {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "Trade unavailable",
                    message: "This preview only includes sample journal trades."
                )
            }
        default:
            ExperienceEmptyState(
                icon: .chart,
                title: "Unavailable in preview",
                message: "Exit preview to use other parts of the app."
            )
        }
    }
}

/// Report detail within preview, no Pro gate or paywall auto-present.
private struct ReportsPreviewReportDetailRouteView: View {
    let reportID: ReportID
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator

    var body: some View {
        Group {
            if PsychologyReportPeriodRef.parse(reportID: reportID) != nil {
                PsychologyReportDetailView(reportID: reportID, data: data)
            } else if let yearRef = TradingReportYearRef.parse(reportID: reportID) {
                YearlyReportDetailView(
                    year: yearRef.year,
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            } else {
                ReportDetailView(
                    reportID: reportID,
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            }
        }
    }
}