import SwiftUI

/// Permanent Home tab root — Apple Fitness / Stocks style analytics cockpit.
struct DashboardHomeView: View {
    @State private var viewModel: DashboardViewModel
    @State private var activityStore = ActivityInboxStore.shared
    @State private var contentRevealed = false
    @State private var deferredDashboardBootstrapStarted = false
    @State private var gettingStartedStore = GettingStartedStore.shared
    @State private var dailyCheckInStore = TraderDailyCheckInStore.shared
    @Bindable private var brokerImportEligibilityStore = BrokerImportEligibilityStore.shared
    @Bindable private var withdrawalsHistory = WithdrawalsHistoryStore.shared
    @State private var entitlementGateRevision = 0
    @State private var dashboardScrollHeaderTracker = FeedScrollAwareHeaderTracker()
    @State private var dashboardScrollChromeHidden = false
    private let navigationCoordinator: NavigationCoordinator
    private let data: DataEnvironment?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabIsActive) private var tabIsActive
    @Environment(\.navigationEnvironment) private var navigationEnvironment

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: DashboardViewModel(
                home: data.home,
                trades: data.trades,
                achievements: data.achievements,
                dailyCheckIns: data.dailyCheckIns,
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
                    emptyDashboardContent
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
                .contextualTourTarget(.dashboardCalendar)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ExperienceHaptics.play(.selection)
                    navigationCoordinator.pushHome(.activity)
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
                .contextualTourTarget(.dashboardNotifications)
            }
        }
        .modifier(
            DashboardScrollAwareHeaderHostModifier(
                reduceMotion: reduceMotion,
                experimentActive: dashboardScrollAwareHeaderActive,
                navigationBarVisibility: dashboardScrollAwareNavigationBarVisibility,
                homePathDepth: navigationEnvironment.store.paths.home.count,
                chromeHidden: $dashboardScrollChromeHidden,
                onReset: resetDashboardScrollAwareHeader
            )
        )
        .refreshable {
            await viewModel.refresh()
            await brokerImportEligibilityStore.refreshAndWait(fromUserAction: true)
        }
        .onChange(of: SessionViewerGate.shared.epoch) { _, _ in
            viewModel.loadIfNeeded()
        }
        .task(id: tabIsActive) {
            guard tabIsActive else { return }
            if let data, let userID = await data.session.currentUserID?.rawValue {
                brokerImportEligibilityStore.hydrateFromDiskIfNeeded(viewerID: userID)
            }
            viewModel.loadIfNeeded()
            viewModel.ensureEquityChartOverlayIfNeeded()
            brokerImportEligibilityStore.loadIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitesting-dashboard-propfirm") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                viewModel.setAccountFilter(.account(PropFirmFixtures.accountID))
            }
            #endif
        }
        .onChange(of: viewModel.phase, initial: true) { _, phase in
            guard tabIsActive else { return }
            guard phase == .loaded || viewModel.summary != nil else { return }
            viewModel.ensureEquityChartOverlayIfNeeded()
            startDeferredDashboardBootstrapIfNeeded()
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            viewModel.handleJournalMutation()
        }
        .onChange(of: ContentMutationStore.shared.revision) { _, _ in
            viewModel.handleContentMutation()
        }
        .onChange(of: TraderDailyCheckInStore.shared.todayCheckIn?.updatedAt) { _, _ in
            if let checkIn = TraderDailyCheckInStore.shared.todayCheckIn {
                SessionDailyCheckInsStore.shared.upsert(checkIn)
                viewModel.handleCheckInMutation()
            }
        }
        .onChange(of: AccountMutationStore.shared.revision) { _, _ in
            viewModel.handleAccountMutation()
            brokerImportEligibilityStore.refreshIfStale(fromUserAction: false)
        }
        .onChange(of: withdrawalsHistory.ledgerEntryCount()) { _, _ in
            viewModel.syncAfterWithdrawalStoreMutation()
        }
        .onChange(of: withdrawalsHistory.completedPropCycleCount()) { _, _ in
            viewModel.syncAfterWithdrawalStoreMutation()
        }
        .onChange(of: BrokerIntegrationMutationStore.shared.revision) { _, _ in
            brokerImportEligibilityStore.refresh(fromUserAction: true)
        }
        .onChange(of: tabIsActive, initial: true) { _, isActive in
            viewModel.setHomeTabActive(isActive)
            guard isActive, brokerImportEligibilityStore.isReady else { return }
            brokerImportEligibilityStore.refreshIfStale(fromUserAction: false)
        }
        .onChange(of: viewModel.summary?.tradeCount) { _, _ in
            revealContentIfNeeded()
        }
        .onDisappear {
            viewModel.onDisappear()
            ContextualTourCoordinator.shared.setDashboardAnalyticsReady(false)
        }
        .onAppear {
            ContextualTourCoordinator.shared.setDashboardAnalyticsReady(dashboardTourAnalyticsReady)
        }
        .onChange(of: dashboardTourAnalyticsReady) { _, ready in
            ContextualTourCoordinator.shared.setDashboardAnalyticsReady(ready)
        }
        .onChange(of: dashboardTourAnalyticsDebugLine, initial: true) { _, line in
            ContextualTourDebug.log(line)
        }
        .accessibilityIdentifier("dashboard.home")
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
        .onChange(of: viewModel.accountFilter) { _, _ in
            resetDashboardScrollAwareHeader()
        }
        .onChange(of: viewModel.dateRange) { _, _ in
            resetDashboardScrollAwareHeader()
        }
    }

    private var dashboardFilterBarChrome: some View {
        DashboardFilterBar(viewModel: viewModel)
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.top, ExperienceSpacing.xs)
            .padding(.bottom, ExperienceSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                colors.backgroundPrimary
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityIdentifier("dashboard.filters")
    }

    private var dashboardScrollAwareHeaderActive: Bool {
        FeedScrollAwareHeaderExperiment.dashboardScrollHeaderEnabled
            && tabIsActive
            && navigationEnvironment.store.paths.home.isEmpty
            && viewModel.summary != nil
    }

    private var dashboardScrollAwareNavigationBarVisibility: Visibility {
        dashboardScrollAwareHeaderActive && dashboardScrollChromeHidden ? .hidden : .visible
    }

    private func resetDashboardScrollAwareHeader() {
        dashboardScrollHeaderTracker.reset()
        dashboardScrollChromeHidden = false
    }

    private var hidesPremiumDashboardCharts: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldHidePremiumDashboardCharts(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: viewModel.ownerAccountsProfileID
        )
    }

    private var restrictsPremiumPsychologyAndAI: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldRestrictPremiumPsychologyAndAI(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: viewModel.ownerAccountsProfileID
        )
    }

    private var restrictsPropFirmMode: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldRestrictPropFirmMode(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: viewModel.ownerAccountsProfileID
        )
    }

    private var psychologyAnalyticsUpgradeSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Psychology Insights")
                .experienceStyle(.headline, color: colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.md)
            Text("Patterns from your trades and daily check-ins")
                .experienceStyle(.footnote, color: colors.tertiaryText)
                .padding(.horizontal, ExperienceSpacing.md)

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text("TraxPro psychology analytics")
                    .experienceStyle(.headline, color: colors.primaryText)
                Text("Advanced psychology analytics and coaching are included with TraxPro.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    ExperienceHaptics.play(.selection)
                    ProUpgradeCoordinator.shared.present(reason: .feature(.premiumAnalytics))
                } label: {
                    Text("Upgrade to TraxPro")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("dashboard.psychology.upgrade.traxpro")
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
                cornerRadius: ExperienceRadius.md,
                style: .continuous
            ))
            .padding(.horizontal, ExperienceSpacing.md)
            .accessibilityIdentifier("dashboard.psychology.traxpro.gate")
        }
        .accessibilityIdentifier("dashboard.psychologyInsights")
    }

    /// Dashboard chrome that owns the tour anchors is on screen.
    /// A new account may still have zero trades and the Getting Started card.
    private var dashboardTourAnalyticsReady: Bool {
        tabIsActive && contentRevealed && viewModel.summary != nil
    }

    private var dashboardTourAnalyticsDebugLine: String {
        let trades = viewModel.summary?.tradeCount
        let summary = viewModel.summary != nil
        return "analytics tab=\(tabIsActive) revealed=\(contentRevealed) summary=\(summary) trades=\(trades.map(String.init) ?? "nil") gettingStarted=\(gettingStartedStore.shouldShowDashboardCard) ready=\(dashboardTourAnalyticsReady)"
    }

    private var accountValueWithdrawalSummary: AccountTrackedBalanceSupport.WithdrawalSummary? {
        guard let account = viewModel.selectedAccount else { return nil }
        return AccountTrackedBalanceSupport.withdrawalSummary(
            account: account,
            payoutCycles: viewModel.payoutCyclesForAccountValueSummary(accountID: account.id),
            ledgerEntries: withdrawalsHistory.ledgerByAccount[account.id] ?? []
        )
    }

    private var emptyDashboardContent: some View {
        ScrollView {
            VStack(spacing: ExperienceSpacing.lg) {
                if gettingStartedStore.shouldShowDashboardCard {
                    GettingStartedCard(
                        store: gettingStartedStore,
                        navigationCoordinator: navigationCoordinator
                    )
                    .padding(.horizontal, ExperienceSpacing.md)
                }
                dashboardQuickActionsGroup(includeBrokerImport: true)
                ExperienceEmptyState(
                    icon: .chart,
                    title: "No trades yet",
                    message: "Log your first trade to unlock the equity curve and analytics."
                )
            }
            .padding(.top, ExperienceSpacing.sm)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                dashboardFilterBarChrome

                if let summary = viewModel.summary {
                    if gettingStartedStore.shouldShowDashboardCard {
                        GettingStartedCard(
                            store: gettingStartedStore,
                            navigationCoordinator: navigationCoordinator
                        )
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.bottom, ExperienceSpacing.sm)
                    }

                    dashboardQuickActionsGroup(includeBrokerImport: true)

                    VStack(alignment: .leading, spacing: 0) {
                        DashboardEquityHero(
                            summary: viewModel.equityHeroSummary ?? summary,
                            periodTitle: viewModel.dateRange.title,
                            title: viewModel.equityHeroTitle,
                            displayEquity: viewModel.equityHeroDisplayValue,
                            chartPoints: viewModel.equityHeroChartPoints,
                            isChartLoading: viewModel.isEquityChartOverlayLoading,
                            withdrawalSummary: accountValueWithdrawalSummary,
                            onWithdrawalSummaryTap: viewModel.openWithdrawalsHistory
                        )

                        DashboardMetricStrip(chips: viewModel.metricChips)
                            .padding(.bottom, ExperienceSpacing.xl)
                    }
                    .contextualTourTarget(.dashboardPerformance)

                    if let propStatus = viewModel.propFirmStatus, !restrictsPropFirmMode {
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
                        onBrowseHoldBucket: { viewModel.browseHoldBucket(label: $0) },
                        hidesPremiumDashboardCharts: hidesPremiumDashboardCharts
                    )
                    .padding(.bottom, ExperienceSpacing.xxl)

                    if !viewModel.psychologyGuardrailNotices.isEmpty {
                        VStack(spacing: ExperienceSpacing.sm) {
                            ForEach(viewModel.psychologyGuardrailNotices) { notice in
                                PsychologyGuardrailBanner(notice: notice) {
                                    viewModel.dismissPsychologyGuardrail(notice)
                                }
                            }
                        }
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.bottom, ExperienceSpacing.sm)
                    }
                    DashboardInsightsSection(
                        title: "Insights",
                        subtitle: "Coaching from your recent activity",
                        insights: summary.insights,
                        unlockProgress: viewModel.psychologyInsightsUnlockProgress
                    )
                    .padding(.bottom, ExperienceSpacing.lg)

                    if restrictsPremiumPsychologyAndAI {
                        psychologyAnalyticsUpgradeSection
                            .padding(.bottom, ExperienceSpacing.xxxl)
                    } else {
                        PsychologyInsightsSection(
                            title: "Psychology Insights",
                            subtitle: "Patterns from your trades and daily check-ins",
                            cards: viewModel.psychologyReport?.dashboardCards ?? [],
                            unlockProgress: viewModel.psychologyInsightsUnlockProgress,
                            onSelect: { card in
                                viewModel.openPsychologyAnalytics(
                                    highlightSection: viewModel.psychologySectionID(for: card.category)
                                )
                            },
                            onViewAll: {
                                viewModel.openPsychologyAnalytics()
                            }
                        )
                        .padding(.bottom, ExperienceSpacing.xxxl)
                    }
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
        .modifier(
            ScrollAwareHeaderScrollModifier(
                isActive: dashboardScrollAwareHeaderActive,
                reduceMotion: reduceMotion,
                debugSurface: "dashboard.scroll",
                trackingMode: .dashboardNavigationBar,
                tracker: $dashboardScrollHeaderTracker,
                chromeHidden: $dashboardScrollChromeHidden
            )
        )
        #if DEBUG
        .background {
            FeedScrollChromeUIKitProbe(label: "dashboard.scroll")
        }
        .onAppear {
            FeedScrollAwareHeaderDiagnostics.logScrollListenerAttached(
                isActive: dashboardScrollAwareHeaderActive,
                surface: "dashboard.scroll"
            )
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard dashboardScrollAwareHeaderActive else { return }
                FeedScrollAwareHeaderDiagnostics.logNoGeometryActionsWarning(
                    surface: "dashboard.scroll",
                    secondsVisible: 3
                )
            }
        }
        #endif
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .onChange(of: ContextualTourCoordinator.shared.scrollTarget) { _, target in
            guard let target else { return }
            if reduceMotion {
                proxy.scrollTo(target, anchor: .center)
            } else {
                withAnimation(ExperienceMotion.navigation) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            ExperienceSkeleton(height: 60, cornerRadius: ExperienceRadius.sm)
                .padding(.horizontal, ExperienceSpacing.md)
            ExperienceSkeleton(height: 60, cornerRadius: ExperienceRadius.sm)
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

    @ViewBuilder
    private func dashboardQuickActionsGroup(includeBrokerImport: Bool) -> some View {
        VStack(spacing: ExperienceSpacing.xs) {
            DailyCheckInCard(store: dailyCheckInStore) {
                ExperienceHaptics.play(.selection)
                navigationCoordinator.present(sheet: .dailyCheckIn)
            }

            if includeBrokerImport, brokerImportEligibilityStore.showsDashboardImportAction {
                DashboardBrokerImportCard(store: brokerImportEligibilityStore) {
                    ExperienceHaptics.play(.selection)
                    navigationCoordinator.present(sheet: .tradeImportReminder)
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.sm)
    }

    private func toneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }

    /// Activity bell, Getting Started, and check-in hydrate after dashboard first paint.
    private func startDeferredDashboardBootstrapIfNeeded() {
        guard !deferredDashboardBootstrapStarted else { return }
        deferredDashboardBootstrapStarted = true
        Task(priority: .utility) {
            await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
            gettingStartedStore.loadIfNeeded()
            dailyCheckInStore.loadIfNeeded()
            brokerImportEligibilityStore.loadIfNeeded()
            if let data {
                activityStore.ensureUnreadBootstrap(
                    notifications: data.notifications,
                    session: data.session,
                    realtimeHub: data.realtimeHub,
                    detailCache: data.detailCache,
                    rpc: data.rpc
                )
            }
        }
    }
}

