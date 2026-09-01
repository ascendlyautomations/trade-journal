import SwiftUI

/// Permanent Home tab root — Apple Fitness / Stocks style analytics cockpit.
struct DashboardHomeView: View {
    @State private var viewModel: DashboardViewModel
    @State private var activityStore = ActivityInboxStore.shared
    @State private var contentRevealed = false
    private let navigationCoordinator: NavigationCoordinator
    private let data: DataEnvironment?

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
                realtimeHub: data.realtimeHub,
                rpc: data.rpc
            )
        )
        self.navigationCoordinator = navigationCoordinator
        self.data = data
    }

    /// Tests / previews.
    init(
        viewModel: DashboardViewModel,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(initialValue: viewModel)
        self.navigationCoordinator = navigationCoordinator
        self.data = nil
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
        .experienceNavigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.openCalendar()
                } label: {
                    ExperienceIcon(icon: .calendar, size: .md, color: colors.primaryText)
                }
                .accessibilityLabel("Calendar")
                .accessibilityIdentifier("dashboard.calendar")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ExperienceHaptics.play(.selection)
                    navigationCoordinator.selectTab(.profile)
                    navigationCoordinator.pushProfile(.activity)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                        if activityStore.unreadCount > 0 {
                            ExperienceBadge(value: activityStore.unreadCount)
                                .offset(x: 10, y: -8)
                        }
                    }
                    .accessibilityLabel(
                        activityStore.unreadCount > 0
                            ? "Activity, \(activityStore.unreadCount) unread"
                            : "Activity"
                    )
                }
                .accessibilityIdentifier("dashboard.activity")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
            if let data {
                activityStore.ensureUnreadBootstrap(
                    notifications: data.notifications,
                    session: data.session,
                    realtimeHub: data.realtimeHub,
                    detailCache: data.detailCache,
                    rpc: data.rpc
                )
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitesting-dashboard-propfirm") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                viewModel.setAccountFilter(.account(PropFirmFixtures.accountID))
            }
            #endif
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            viewModel.handleJournalMutation()
        }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            viewModel.handleAccountMutation()
        }
        .onChange(of: viewModel.summary?.tradeCount) { _, _ in
            revealContentIfNeeded()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .accessibilityIdentifier("dashboard.home")
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DashboardFilterBar(viewModel: viewModel)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)
                    .padding(.bottom, ExperienceSpacing.sm)

                if let summary = viewModel.summary {
                    DashboardEquityHero(
                        summary: summary,
                        periodTitle: viewModel.dateRange.title,
                        title: viewModel.equityHeroTitle,
                        displayEquity: viewModel.equityHeroDisplayValue,
                        chartPoints: viewModel.equityHeroChartPoints
                    )

                    DashboardMetricStrip(chips: viewModel.metricChips)
                        .padding(.bottom, ExperienceSpacing.xl)

                    if let propStatus = viewModel.propFirmStatus {
                        PropFirmStatusCard(
                            snapshot: propStatus,
                            onOpenDetails: { viewModel.openPropFirmDetails() }
                        )
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.bottom, ExperienceSpacing.xl)
                    }

                    sectionHeader(
                        "Performance",
                        subtitle: "Outcome quality for this period"
                    )
                    performanceCardsGrid
                        .padding(.bottom, ExperienceSpacing.lg)

                    DashboardChartsSection(
                        summary: summary,
                        onBrowseWins: { viewModel.browseWins() },
                        onBrowseLosses: { viewModel.browseLosses() },
                        onBrowseSession: { viewModel.browseSession($0) },
                        onBrowseWeekday: { viewModel.browseWeekday(label: $0) },
                        onBrowseHour: { viewModel.browseHour(label: $0) },
                        onBrowseLong: { viewModel.browseLong() },
                        onBrowseShort: { viewModel.browseShort() },
                        onBrowseHoldBucket: { viewModel.browseHoldBucket(label: $0) }
                    )
                    .padding(.bottom, ExperienceSpacing.xxl)

                    sectionHeader(
                        "Insights",
                        subtitle: "Coaching from your recent activity"
                    )
                    DashboardInsightsSection(insights: summary.insights, showsTitle: false)
                        .padding(.bottom, ExperienceSpacing.xxxl)
                }
            }
            .opacity(contentRevealed || reduceMotion ? 1 : 0.001)
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
                value: contentRevealed
            )
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: viewModel.dateRange
            )
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: viewModel.accountFilter
            )
            .onAppear {
                revealContentIfNeeded()
            }
        }
    }

    private func revealContentIfNeeded() {
        guard viewModel.summary != nil else { return }
        guard !contentRevealed else { return }
        ExperienceMotion.withAnimation(
            ExperienceMotion.navigation,
            reduceMotion: reduceMotion
        ) {
            contentRevealed = true
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
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text(chip.value)
                        .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(toneColor(chip.tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
                    cornerRadius: ExperienceRadius.sm,
                    style: .continuous
                ))
                .accessibilityIdentifier("dashboard.card.\(chip.id)")
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
            if let subtitle {
                Text(subtitle)
                    .experienceStyle(.footnote, color: colors.tertiaryText)
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.md)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(subtitle.map { "\(title). \($0)" } ?? title)
    }

    private var skeleton: some View {
        VStack(spacing: ExperienceSpacing.md) {
            ExperienceSkeleton(height: 36, cornerRadius: ExperienceRadius.sm)
                .padding(.horizontal, ExperienceSpacing.md)
            ExperienceSkeleton(height: 88, cornerRadius: ExperienceRadius.sm)
                .padding(.horizontal, ExperienceSpacing.md)
            ExperienceSkeleton(height: 280, cornerRadius: ExperienceRadius.md)
                .padding(.horizontal, ExperienceSpacing.md)
            ExperienceSkeleton(height: 56, cornerRadius: ExperienceRadius.md)
                .padding(.horizontal, ExperienceSpacing.md)
            HStack(spacing: ExperienceSpacing.sm) {
                ExperienceSkeleton(height: 64, cornerRadius: ExperienceRadius.sm)
                ExperienceSkeleton(height: 64, cornerRadius: ExperienceRadius.sm)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            Spacer()
        }
        .padding(.top, ExperienceSpacing.md)
        .accessibilityIdentifier("dashboard.skeleton")
        .transition(.opacity)
    }

    private func toneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }
}
