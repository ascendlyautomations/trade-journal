import SwiftUI

/// Trading Report detail, real web-parity sections (no fake placeholders).
struct ReportDetailView: View {
    @State private var viewModel: ReportDetailViewModel

    @Environment(\.themeColors) private var colors
    private let tradingPreferences: (any TradingPreferencesRepository)?
    private let navigationCoordinator: NavigationCoordinator?

    init(
        reportID: ReportID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: ReportDetailViewModel(
                reportID: reportID,
                tradingReports: data.tradingReports,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
        tradingPreferences = data.tradingPreferences
        self.navigationCoordinator = navigationCoordinator
    }

    init(viewModel: ReportDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
        tradingPreferences = nil
        navigationCoordinator = nil
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                loadingContent
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't open report",
                    message: message,
                    onRetry: { Task { await viewModel.retry() } }
                )
            case .loaded:
                detailScroll
            }
        }
        .experienceScreenBackground()
        .modifier(
            ReportDetailPerformanceNavigationChrome(
                periodLabel: viewModel.navigationPeriodLabel,
                fallbackTitle: viewModel.title
            )
        )
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.bootstrapIfNeeded()
        }
        .accessibilityIdentifier("reports.detail")
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let navigationCoordinator {
                    TradingPreferenceDiscoverySlot(
                        surface: .analytics,
                        userID: SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) },
                        repository: tradingPreferences,
                        localHasTrade: false,
                        navigationCoordinator: navigationCoordinator
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)
                }

                ReportDetailBlocksView(
                    blocks: viewModel.blocks,
                    bestTrade: viewModel.bestTrade,
                    onOpenBestTrade: { viewModel.openBestTrade() }
                )
                .padding(.top, ExperienceSpacing.xs)

                ComplianceDisclaimerFootnote(text: ComplianceDisclaimerCopy.performanceReport)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ReportDetailLayout.sectionSpacing)
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            ProgressView("Generating report…")
                .tint(colors.accent)
                .padding(.top, ExperienceSpacing.xxl)
            ExperienceSkeleton(height: 110, cornerRadius: ExperienceRadius.card)
            ForEach(0..<3, id: \.self) { _ in
                ExperienceSkeleton(height: 128, cornerRadius: ExperienceRadius.card)
            }
            Spacer()
        }
        .padding(ExperienceSpacing.md)
        .accessibilityIdentifier("reports.detail.skeleton")
    }
}