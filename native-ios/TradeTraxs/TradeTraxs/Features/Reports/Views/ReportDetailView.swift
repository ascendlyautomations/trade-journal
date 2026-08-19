import SwiftUI

/// Trading Report detail — real web-parity sections (no fake placeholders).
struct ReportDetailView: View {
    @State private var viewModel: ReportDetailViewModel

    @Environment(\.themeColors) private var colors

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
    }

    init(viewModel: ReportDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
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
        .experienceNavigationTitle(viewModel.title)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.bootstrapIfNeeded()
        }
        .accessibilityIdentifier("reports.detail")
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                header
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)

                ReportDetailBlocksView(
                    blocks: viewModel.blocks,
                    bestTrade: viewModel.bestTrade,
                    onOpenBestTrade: { viewModel.openBestTrade() }
                )
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Intelligence Report")
                .experienceStyle(.caption2, color: colors.accent)
                .textCase(.uppercase)
                .tracking(0.6)

            if let range = viewModel.dateRangeLabel {
                Text(range)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
            }

            if let source = viewModel.report?.summarySource {
                Text(source == "ai" ? "AI summary" : "Journal insights")
                    .experienceStyle(.footnote, color: colors.tertiaryText)
            }
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            colors.accent.opacity(0.14),
                            colors.fillSecondary.opacity(0.6),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .accessibilityIdentifier("reports.detail.header")
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
