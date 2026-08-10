import SwiftUI

/// Permanent Home tab root — Apple Fitness / Stocks style analytics cockpit.
struct DashboardHomeView: View {
    @State private var viewModel: DashboardViewModel
    private let imagePipeline: any ImagePipeline
    private let engagementStore: EngagementStore
    private let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: DashboardViewModel(
                home: data.home,
                trades: data.trades,
                achievements: data.achievements,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                realtimeHub: data.realtimeHub
            )
        )
        self.imagePipeline = data.imagePipeline
        self.engagementStore = data.engagementStore
        self.navigationCoordinator = navigationCoordinator
    }

    /// Tests / previews.
    init(
        viewModel: DashboardViewModel,
        imagePipeline: any ImagePipeline,
        engagementStore: EngagementStore,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
        self.engagementStore = engagementStore
        self.navigationCoordinator = navigationCoordinator
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if viewModel.summary == nil {
                    skeleton
                } else {
                    scrollContent
                }
            case .failed(let message):
                if viewModel.summary == nil {
                    ExperienceErrorState(
                        title: "Couldn't load dashboard",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                } else {
                    scrollContent
                }
            case .loaded:
                if viewModel.summary == nil {
                    ExperienceEmptyState(
                        icon: .chart,
                        title: "No trades yet",
                        message: "Log your first trade to unlock the equity curve and analytics."
                    )
                } else {
                    scrollContent
                }
            }
        }
        .experienceScreenBackground()
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Activity", systemImage: "bell") {
                    navigationCoordinator.open(.profile(.activity))
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitesting-dashboard-propfirm") {
                // Wait for fixtures, then select the prop account.
                try? await Task.sleep(nanoseconds: 200_000_000)
                viewModel.setAccountFilter(.account(PropFirmFixtures.accountID))
            }
            #endif
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .accessibilityIdentifier("dashboard.home")
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                DashboardFilterBar(viewModel: viewModel)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)

                if let summary = viewModel.summary {
                    DashboardEquityHero(summary: summary)

                    if let propStatus = viewModel.propFirmStatus {
                        PropFirmStatusCard(
                            snapshot: propStatus,
                            onOpenDetails: { viewModel.openPropFirmDetails() }
                        )
                        .padding(.horizontal, ExperienceSpacing.md)
                    }

                    sectionHeader("Performance")
                    DashboardMetricStrip(chips: viewModel.metricChips)

                    sectionHeader("Key Stats")
                    performanceCardsGrid

                    sectionHeader("Charts")
                    DashboardChartsSection(summary: summary)

                    DashboardRecentTradesSection(
                        trades: viewModel.recentTrades,
                        accountNames: viewModel.accountNames,
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        onOpen: { viewModel.openTrade($0) },
                        onSeeAll: { viewModel.openTradesList() }
                    )

                    DashboardInsightsSection(insights: summary.insights)
                        .padding(.bottom, ExperienceSpacing.xl)
                }
            }
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: viewModel.dateRange
            )
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: viewModel.accountFilter
            )
        }
    }

    private var performanceCardsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: ExperienceSpacing.sm),
                GridItem(.flexible(), spacing: ExperienceSpacing.sm),
            ],
            spacing: ExperienceSpacing.sm
        ) {
            ForEach(viewModel.performanceCards) { chip in
                VStack(alignment: .leading, spacing: 4) {
                    Text(chip.label)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                    Text(chip.value)
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(toneColor(chip.tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(ExperienceSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.fillSecondary.opacity(0.45), in: RoundedRectangle(
                    cornerRadius: ExperienceRadius.md,
                    style: .continuous
                ))
                .accessibilityIdentifier("dashboard.card.\(chip.id)")
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .experienceStyle(.footnote, color: colors.tertiaryText)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.xs)
    }

    private var skeleton: some View {
        VStack(spacing: ExperienceSpacing.md) {
            ExperienceSkeleton(height: 36, cornerRadius: ExperienceRadius.sm)
                .padding(.horizontal, ExperienceSpacing.md)
            ExperienceSkeleton(height: 260, cornerRadius: ExperienceRadius.md)
                .padding(.horizontal, ExperienceSpacing.md)
            ExperienceSkeleton(height: 72, cornerRadius: ExperienceRadius.sm)
                .padding(.horizontal, ExperienceSpacing.md)
            Spacer()
        }
        .padding(.top, ExperienceSpacing.md)
        .accessibilityIdentifier("dashboard.skeleton")
    }

    private func toneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }
}
