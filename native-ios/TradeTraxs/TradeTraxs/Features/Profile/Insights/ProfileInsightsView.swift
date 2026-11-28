import SwiftUI

private enum ProfileInsightsEngagementRateInfo {
    static func popoverBody(definition: String?) -> String {
        if let definition, !definition.isEmpty {
            return definition
        }
        return "Total engagement divided by content views in this period. Self-views are excluded. Stories are included in content views."
    }
}

private enum TopContentSort: String, CaseIterable, Identifiable {
    case views
    case engagement

    var id: String { rawValue }

    var label: String {
        switch self {
        case .views: return "Views"
        case .engagement: return "Engagement"
        }
    }
}

struct ProfileInsightsView: View {
    @State private var viewModel: ProfileInsightsViewModel
    @State private var topContentSort: TopContentSort = .views
    @State private var periodPickerSelection: ProfileInsightsPeriodOption = .days30
    let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors

    init(rpc: any RPCClient, navigationCoordinator: NavigationCoordinator) {
        self.navigationCoordinator = navigationCoordinator
        _viewModel = State(
            initialValue: ProfileInsightsViewModel(
                repository: ProfileInsightsRepository(rpc: rpc)
            )
        )
    }

    var body: some View {
        Group {
            if let bootstrap = viewModel.displayedBootstrap {
                loadedBody(bootstrap)
            } else {
                switch viewModel.phase {
                case .idle, .loading:
                    ExperienceIndeterminateProgress()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ExperienceErrorState(title: "Couldn't load insights", message: message) {
                        viewModel.reload()
                    }
                case .loaded:
                    EmptyView()
                }
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isRefreshing {
                ExperienceIndeterminateProgress()
                    .padding(.top, ExperienceSpacing.sm)
            }
        }
        .experienceScreenBackground()
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.loadIfNeeded() }
        .onAppear {
            periodPickerSelection = viewModel.periodPickerOption
        }
        .onChange(of: viewModel.periodPickerOption) { _, option in
            periodPickerSelection = option
        }
        .sheet(isPresented: $viewModel.showsCustomDateSheet) {
            ProfileInsightsCustomDateRangeSheet(viewModel: viewModel)
        }
        .accessibilityIdentifier("profile.insights.root")
    }

    @ViewBuilder
    private func loadedBody(_ bootstrap: ProfileInsightsBootstrapV1) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                Picker("Range", selection: $periodPickerSelection) {
                    ForEach(ProfileInsightsPeriodOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, ExperienceSpacing.md)
                .onChange(of: periodPickerSelection) { _, new in
                    if new == .custom {
                        viewModel.openCustomDateSheet()
                        periodPickerSelection = viewModel.periodPickerOption
                        return
                    }
                    viewModel.setPeriodOption(new)
                }

                coverageNotes(bootstrap.data.coverage)

                metricGrid(bootstrap)

                if let points = bootstrap.data.series.follower_net_per_day?.map(chartPoint) {
                    AdminUsageLineChartSection(
                        title: "Net follower growth",
                        subtitle: "Follows minus unfollows per day after follower event tracking started.",
                        points: points
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                }
                if let points = bootstrap.data.series.new_followers_per_day?.map(chartPoint) {
                    AdminUsageLineChartSection(
                        title: "New followers",
                        subtitle: "Follow events per day.",
                        points: points
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                }
                if let points = bootstrap.data.series.unfollows_per_day?.map(chartPoint) {
                    AdminUsageLineChartSection(
                        title: "Unfollows",
                        subtitle: "Unfollow events per day.",
                        points: points
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                }

                kindBreakdown(bootstrap.data.content_views_by_kind ?? [:])

                engagementBreakdown(bootstrap.data.summary)

                topContent(bootstrap, sort: topContentSort)
            }
            .padding(.vertical, ExperienceSpacing.md)
        }
    }

    private func coverageNotes(_ coverage: ProfileInsightsBootstrapV1.Coverage) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            if let since = coverage.profile_visits_since {
                Text("Profile visits tracked since \(formatCoverage(since)).")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
            if let since = coverage.content_views_since {
                Text("Content views tracked since \(formatCoverage(since)).")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            } else {
                Text("Content view history starts when this update is deployed.")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
            if coverage.follower_events_since == nil {
                Text("Follower unfollows are tracked from deployment forward; earlier net growth may be incomplete.")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func metricGrid(_ bootstrap: ProfileInsightsBootstrapV1) -> some View {
        let s = bootstrap.data.summary
        let p = bootstrap.data.summary_prior
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: ExperienceSpacing.sm
        ) {
            metricCard("Profile visits", value: s.profile_views, prior: p.profile_views)
            metricCard("Unique visitors", value: s.unique_visitors, prior: p.unique_visitors)
            metricCard("Content views", value: s.content_views, prior: p.content_views)
            metricCard("Net followers", value: s.net_followers, prior: p.net_followers)
            metricCard("Engagement", value: s.total_engagement, prior: p.total_engagement)
            engagementRateCard(
                rate: s.engagement_rate,
                infoBody: ProfileInsightsEngagementRateInfo.popoverBody(
                    definition: bootstrap.meta.engagement_rate_definition
                )
            )
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func engagementRateCard(rate: Double?, infoBody: String) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("Engagement rate")
                    .experienceStyle(.caption, color: colors.secondaryText)
                AnalyticsMetricInfoButton(
                    title: "Engagement rate",
                    bodyText: infoBody,
                    accessibilityID: "profile.insights.engagementRate.info"
                )
                Spacer(minLength: 0)
            }
            if let rate {
                Text(String(format: "%.1f%%", rate * 100))
                    .experienceStyle(.title3, color: colors.primaryText)
            } else {
                Text("—")
                    .experienceStyle(.title3, color: colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.sm)
        .background(colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md))
    }

    private func metricCard(_ title: String, value: Int?, prior: Int?, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption, color: colors.secondaryText)
            if let value {
                Text("\(value)\(suffix ?? "")")
                    .experienceStyle(.title3, color: colors.primaryText)
                if let pct = ProfileInsightsMath.percentChange(current: value, prior: prior) {
                    Text(String(format: "%+.0f%% vs prior period", pct))
                        .experienceStyle(.caption2, color: pct >= 0 ? colors.profit : colors.loss)
                }
            } else {
                Text("—")
                    .experienceStyle(.title3, color: colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.sm)
        .background(colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md))
    }

    private func kindBreakdown(_ kinds: [String: Int]) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Content views by type")
                .experienceStyle(.headline, color: colors.primaryText)
            ForEach(Array(kinds.sorted(by: { $0.key < $1.key })), id: \.key) { entry in
                HStack {
                    Text(kindLabel(entry.key))
                    Spacer()
                    Text(NumberDisplay.integer(entry.value))
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func engagementBreakdown(_ summary: ProfileInsightsBootstrapV1.Summary) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Engagement breakdown")
                .experienceStyle(.headline, color: colors.primaryText)
            row("Likes", summary.likes)
            row("Comments", summary.comments)
            row("Saves", summary.saves)
            row("Shares (initiated)", summary.shares_initiated)
            row("Shares (completed)", summary.shares_completed)
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func row(_ label: String, _ value: Int?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.map { NumberDisplay.integer($0) } ?? "—")
                .experienceStyle(.subheadline, color: colors.secondaryText)
        }
    }

    private func topContent(
        _ bootstrap: ProfileInsightsBootstrapV1,
        sort: TopContentSort
    ) -> some View {
        let items: [ProfileInsightsBootstrapV1.TopContent] = {
            switch sort {
            case .views:
                return bootstrap.data.top_content_by_views
                    ?? bootstrap.data.top_content
                    ?? []
            case .engagement:
                return bootstrap.data.top_content_by_engagement
                    ?? bootstrap.data.top_content
                    ?? []
            }
        }()
        return VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                Text("Top content")
                    .experienceStyle(.headline, color: colors.primaryText)
                Spacer()
                Picker("Sort", selection: $topContentSort) {
                    ForEach(TopContentSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                .pickerStyle(.menu)
            }
            if items.isEmpty {
                Text("No ranked content in this period yet.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                ForEach(items) { item in
                    Button {
                        openContent(item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kindLabel(item.content_kind))
                                    .experienceStyle(.subheadline, color: colors.primaryText)
                                Text("\(item.views) views · \(item.engagement) engagement")
                                    .experienceStyle(.caption, color: colors.tertiaryText)
                            }
                            Spacer()
                            ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
                        }
                    }
                    .buttonStyle(.experiencePlain)
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func openContent(_ item: ProfileInsightsBootstrapV1.TopContent) {
        switch item.content_kind {
        case "post":
            navigationCoordinator.open(AppDestination.profile(.trade(TradeID(item.content_id))))
        case "profile_post":
            navigationCoordinator.open(AppDestination.profile(.post(PostID(item.content_id))))
        case "reel":
            navigationCoordinator.open(AppDestination.profile(.reel(ReelID(item.content_id))))
        case "achievement_post":
            navigationCoordinator.open(AppDestination.profile(.achievement(AchievementID(item.content_id))))
        default:
            break
        }
    }

    private func kindLabel(_ raw: String) -> String {
        switch raw {
        case "post": return "Trades"
        case "profile_post": return "Posts"
        case "reel": return "Clips"
        case "achievement_post": return "Achievements"
        case "story": return "Stories"
        default: return raw.capitalized
        }
    }

    private func chartPoint(_ row: ProfileInsightsBootstrapV1.DayCount) -> AdminUsageDailyCount {
        AdminUsageDailyCount(day: row.day, count: row.count)
    }

    private func formatCoverage(_ iso: String) -> String {
        TradingCalendarDay.displayDate(from: String(iso.prefix(10)))
    }
}