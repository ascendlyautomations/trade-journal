import SwiftUI

struct AdminChartsView: View {
    let data: DataEnvironment

    @State private var viewModel: AdminChartsViewModel

    init(data: DataEnvironment) {
        self.data = data
        _viewModel = State(initialValue: AdminChartsViewModel(repository: data.adminUsageAnalytics))
    }

    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                Picker("Range", selection: $viewModel.selectedRange) {
                    ForEach(AdminChartsRange.allCases) { range in
                        Text(range.menuLabel).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, ExperienceSpacing.md)
                .onChange(of: viewModel.selectedRange) { _, _ in
                    Task { await viewModel.onRangeChanged() }
                }

                if viewModel.isLoading, viewModel.bundle == nil {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, ExperienceSpacing.xl)
                } else if let error = viewModel.errorMessage {
                    SettingsInlineError(message: error) {
                        Task { await viewModel.load(force: true) }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                } else if let bundle = viewModel.bundle, let summary = viewModel.summary {
                    summaryGrid(summary, bundle: bundle)
                    charts(bundle)
                }
            }
            .padding(.bottom, ExperienceSpacing.xl)
        }
        .adminScreenHeading("Charts")
        .accessibilityIdentifier("admin.charts")
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func summaryGrid(_ summary: AdminChartsSummary, bundle: AdminUsageAnalyticsBundle) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: ExperienceSpacing.sm
        ) {
            summaryCard("DAU (latest day)", NumberDisplay.integer(summary.latestDailyActiveUsers))
            summaryCard("DAU (24h roll)", NumberDisplay.integer(summary.rollingDailyActiveUsers))
            summaryCard("New users", NumberDisplay.integer(summary.newUsersInPeriod))
            summaryCard("Trades", NumberDisplay.integer(summary.tradesInPeriod))
            summaryCard("Posts", NumberDisplay.integer(summary.postsInPeriod))
            summaryCard("Avg trades/day", NumberDisplay.decimal(summary.averageTradesPerDay, minimumFractionDigits: 1, maximumFractionDigits: 1))
            summaryCard("Avg posts/day", NumberDisplay.decimal(summary.averagePostsPerDay, minimumFractionDigits: 1, maximumFractionDigits: 1))
            summaryCard("Total users", NumberDisplay.integer(bundle.totalUsers))
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func summaryCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption, color: colors.tertiaryText)
            Text(value)
                .experienceStyle(.title3, color: colors.primaryText)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.md)
        .experienceFloatingPanelBackground(
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
    }

    @ViewBuilder
    private func charts(_ bundle: AdminUsageAnalyticsBundle) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            AdminUsageLineChartSection(
                title: "Daily Active Users",
                subtitle: AdminUsageAnalyticsDefinition.dailyActiveUsersPerDay,
                points: bundle.series.activeUsersPerDay,
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.activeUsersPerDay)
            )
            AdminUsageLineChartSection(
                title: "New Signups",
                subtitle: "New profiles created per UTC day.",
                points: bundle.series.usersPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.usersPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.usersPerDay)
            )
            AdminUsageLineChartSection(
                title: "Posts Per Day",
                subtitle: "Feed posts created per UTC day.",
                points: bundle.series.postsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.postsPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.postsPerDay)
            )
            AdminUsageLineChartSection(
                title: "Trades Added Per Day",
                subtitle: "Trades logged per UTC day.",
                points: bundle.series.tradesPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.tradesPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.tradesPerDay)
            )
            AdminUsageLineChartSection(
                title: "Reels / Clips Per Day",
                subtitle: "Reels published per UTC day.",
                points: bundle.series.reelsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.reelsPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.reelsPerDay)
            )
            AdminUsageLineChartSection(
                title: "Comments Per Day",
                subtitle: "Comments created per UTC day.",
                points: bundle.series.commentsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.commentsPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.commentsPerDay)
            )
            AdminUsageLineChartSection(
                title: "Likes Per Day",
                subtitle: "Likes created per UTC day.",
                points: bundle.series.likesPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.likesPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.likesPerDay)
            )
            AdminUsageLineChartSection(
                title: "Follows Per Day",
                subtitle: "New follow relationships per UTC day.",
                points: bundle.series.followsPerDay,
                periodTotal: AdminUsageAnalyticsMath.totalCount(bundle.series.followsPerDay),
                periodAverage: AdminUsageAnalyticsMath.averagePerDay(bundle.series.followsPerDay)
            )
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }
}
