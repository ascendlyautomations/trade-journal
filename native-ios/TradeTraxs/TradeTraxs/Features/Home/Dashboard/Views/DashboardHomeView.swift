import SwiftUI

/// Permanent Home tab root, Apple Fitness / Stocks style analytics cockpit.
struct DashboardHomeView: View {
    @State private var viewModel: DashboardViewModel
    @State private var activityStore = ActivityInboxStore.shared
    @State private var contentRevealed: Bool
    @State private var scrollAnchor: DashboardScrollAnchor
    @State private var gettingStartedStore = GettingStartedStore.shared
    @State private var dailyCheckInStore = TraderDailyCheckInStore.shared
    @Bindable private var brokerImportEligibilityStore = BrokerImportEligibilityStore.shared
    @Bindable private var withdrawalsHistory = WithdrawalsHistoryStore.shared
    @State private var entitlementGateRevision = 0
    private let navigationCoordinator: NavigationCoordinator
    private let data: DataEnvironment?
    private let embeddedInTraxsProPreview: Bool

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabIsActive) private var tabIsActive
    @Environment(\.navigationEnvironment) private var navigationEnvironment

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        retainsTabPresentation: Bool = true
    ) {
        let model = DashboardTabModelStore.model(retainsTabPresentation: retainsTabPresentation) {
            DashboardViewModel(
                home: data.home,
                trades: data.trades,
                achievements: data.achievements,
                dailyCheckIns: data.dailyCheckIns,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                realtimeHub: data.realtimeHub,
                rpc: data.rpc,
                tradingPreferences: data.tradingPreferences
            )
        }
        _viewModel = State(initialValue: model)
        _contentRevealed = State(initialValue: model.summary != nil)
        let anchor = DashboardTabModelStore.scrollAnchor(restoredOffset: model.retainedScrollOffset)
        _scrollAnchor = State(initialValue: anchor)
        self.navigationCoordinator = navigationCoordinator
        self.data = data
        self.embeddedInTraxsProPreview = false
    }

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        embeddedInTraxsProPreview: Bool
    ) {
        self.embeddedInTraxsProPreview = embeddedInTraxsProPreview
        let model = DashboardViewModel(
            home: data.home,
            trades: data.trades,
            achievements: data.achievements,
            dailyCheckIns: data.dailyCheckIns,
            session: data.session,
            detailCache: data.detailCache,
            navigationCoordinator: navigationCoordinator,
            realtimeHub: data.realtimeHub,
            rpc: data.rpc,
            tradingPreferences: data.tradingPreferences,
            loadsTraxsProPreviewSampleOnly: embeddedInTraxsProPreview
        )
        _viewModel = State(initialValue: model)
        _contentRevealed = State(initialValue: model.summary != nil)
        let anchor = DashboardTabModelStore.scrollAnchor(restoredOffset: model.retainedScrollOffset)
        _scrollAnchor = State(initialValue: anchor)
        self.navigationCoordinator = navigationCoordinator
        self.data = data
    }

    /// Tests / previews.
    init(
        viewModel: DashboardViewModel,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(initialValue: viewModel)
        _contentRevealed = State(initialValue: viewModel.summary != nil)
        let anchor = DashboardTabModelStore.scrollAnchor(restoredOffset: viewModel.retainedScrollOffset)
        _scrollAnchor = State(initialValue: anchor)
        self.navigationCoordinator = navigationCoordinator
        self.data = nil
        self.embeddedInTraxsProPreview = false
    }

    var body: some View {
        applyDashboardNotificationModifiers(
            to: applyDashboardLifecycleModifiers(to: dashboardRoot)
        )
    }

    @ViewBuilder
    private var dashboardRoot: some View {
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
                    dashboardFailedContent(message: message)
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
        .sheet(isPresented: $viewModel.showsScopeFilterSheet) {
            DashboardScopeFilterSheet(viewModel: viewModel)
                .experienceSheetChrome()
        }
        .sheet(isPresented: $viewModel.showsEquityDrawdownSettings) {
            DashboardEquityDrawdownSettingsSheet(
                accountName: viewModel.selectedAccount?.name ?? "Live account",
                limitDigits: $viewModel.equityDrawdownLimitDraft,
                limitType: $viewModel.equityDrawdownTypeDraft,
                floorCapDigits: $viewModel.equityDrawdownFloorCapDraft,
                isSaving: viewModel.isSavingEquityDrawdownSettings,
                errorMessage: viewModel.equityDrawdownSettingsError,
                onSave: {
                    Task { await viewModel.saveEquityDrawdownSettings() }
                },
                onCancel: viewModel.cancelEquityDrawdownSettings
            )
        }
        .experienceNavigationTitle("Dashboard")
        .toolbar {
            if !embeddedInTraxsProPreview {
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
            }
            }
        }
        .modifier(
            DashboardScrollHeaderOpaqueNavBarLifecycleModifier(
                experimentActive: dashboardOpaqueNavBarExperimentActive,
                colors: colors
            )
        )
        .refreshable {
            await viewModel.refresh()
            await brokerImportEligibilityStore.refreshAndWait(fromUserAction: true)
        }
    }

    @ViewBuilder
    private func applyDashboardLifecycleModifiers<Content: View>(to content: Content) -> some View {
        content
        .onChange(of: SessionViewerGate.shared.epoch) { _, _ in
            viewModel.loadIfNeeded()
        }
        .task(id: tabIsActive) {
            guard tabIsActive else { return }
            if let data, let userID = await data.session.currentUserID?.rawValue {
                brokerImportEligibilityStore.hydrateFromDiskIfNeeded(viewerID: userID)
            }
            viewModel.loadIfNeeded()
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
        .onChange(of: withdrawalsHistory.achievementPayouts.count) { _, _ in
            viewModel.syncAfterWithdrawalStoreMutation()
        }
        .onChange(of: BrokerIntegrationMutationStore.shared.revision) { _, _ in
            brokerImportEligibilityStore.refresh(fromUserAction: true)
        }
        .onChange(of: tabIsActive, initial: true) { _, isActive in
            if !isActive {
                preserveScrollOffset()
            }
            viewModel.setHomeTabActive(isActive)
            if isActive {
                viewModel.ensureEquityChartOverlayIfNeeded()
            }
            guard isActive, brokerImportEligibilityStore.isReady else { return }
            brokerImportEligibilityStore.refreshIfStale(fromUserAction: false)
        }
        .onChange(of: viewModel.summary, initial: true) { _, summary in
            if summary != nil {
                contentRevealed = true
            }
        }
        .onChange(of: viewModel.summary?.tradeCount) { _, _ in
            revealContentIfNeeded()
            viewModel.refreshPsychologyUnlockMetrics()
        }
        .onDisappear {
            preserveScrollOffset()
            viewModel.onDisappear()
            ContextualTourCoordinator.shared.setDashboardAnalyticsReady(false)
        }
        .onAppear {
            PsychologyAnalyticsPresentationBridge.bind(viewModel)
            TradingRulesCompliancePresentationBridge.bind(viewModel)
            ContextualTourCoordinator.shared.setDashboardAnalyticsReady(dashboardTourAnalyticsReady)
        }
        .onChange(of: dashboardTourAnalyticsReady) { _, ready in
            ContextualTourCoordinator.shared.setDashboardAnalyticsReady(ready)
        }
        .onChange(of: viewModel.listScrollPresentationEpoch) { _, _ in
            scrollAnchor.resetToTop()
        }
        .onChange(of: dashboardTourAnalyticsDebugLine, initial: true) { _, line in
            ContextualTourDebug.log(line)
        }
        .accessibilityIdentifier("dashboard.home")
    }

    @ViewBuilder
    private func applyDashboardNotificationModifiers<Content: View>(to content: Content) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
        .task(id: dashboardEntitlementVerificationActive) {
            if dashboardEntitlementVerificationActive {
                refreshDashboardEntitlementIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradingPreferencesDidChange)) { _ in
            if let profileID = viewModel.profileIDForTradingRulesCache {
                TradingRulesCompliancePreferencesCache.invalidate(profileID: profileID)
            }
            TradingRulesComplianceRecomputeCoordinator.reset()
            viewModel.refreshTradingPreferencesAfterEditorSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradingRulesComplianceOwnerTradesChanged)) { notification in
            viewModel.handleTradingRulesOwnerTradesChangedNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .traxsProCanonicalJournalPreviewDidEnd)) { _ in
            guard !embeddedInTraxsProPreview else { return }
            viewModel.restoreAfterCanonicalJournalPreviewEnded()
        }
    }

    @ViewBuilder
    private var dashboardScrollFilterBar: some View {
        if showsDashboardFilterBar {
            dashboardFilterBarChrome
        }
    }

    private var showsDashboardFilterBar: Bool {
        guard !embeddedInTraxsProPreview else { return false }
        switch viewModel.phase {
        case .idle:
            return viewModel.hasLoaded || !viewModel.accounts.isEmpty
        case .loading, .loaded, .failed:
            return true
        }
    }

    private var dashboardFilterBarChrome: some View {
        DashboardFilterBar(viewModel: viewModel)
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.top, ExperienceSpacing.xs)
            .padding(.bottom, ExperienceSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.filters")
    }

    private func dashboardFailedContent(message: String) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: ExperienceSpacing.lg) {
                dashboardScrollFilterBar
                ExperienceErrorState(
                    title: "Couldn't load dashboard",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            }
            .padding(.top, ExperienceSpacing.sm)
            .experienceDisablesSystemScrollToTop()
        }
        .dashboardHorizontalLock()
        .scrollPosition(scrollAnchor.binding)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Opaque nav bar on the Dashboard root so header chrome stays visually stable.
    private var dashboardOpaqueNavBarExperimentActive: Bool {
        DashboardScrollHeaderOpaqueNavBarExperiment.matchesFeedOpaqueNavigationBar
            && tabIsActive
            && navigationEnvironment.store.paths.home.isEmpty
            && viewModel.summary != nil
    }

    private var premiumAnalyticsPresentation: ProPremiumFeaturePresentation {
        if embeddedInTraxsProPreview {
            return .unrestricted
        }
        _ = entitlementGateRevision
        return ProMonetizationPolicy.premiumFeaturePresentation(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: viewModel.ownerAccountsProfileID
        )
    }

    private var dashboardEntitlementVerificationActive: Bool {
        premiumAnalyticsPresentation == .verifyingEntitlement
    }

    private func refreshDashboardEntitlementIfNeeded() {
        guard let data else { return }
        Task { await TraxProEntitlementRefreshAction.refresh(data: data) }
    }

    private var restrictsPropFirmMode: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldRestrictPropFirmMode(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: viewModel.ownerAccountsProfileID
        )
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

    private var discoveryUserID: ProfileID? {
        SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
    }

    private var accountValueWithdrawalSummary: AccountTrackedBalanceSupport.WithdrawalSummary? {
        guard let account = viewModel.selectedAccount else { return nil }
        return AccountTrackedBalanceSupport.withdrawalSummary(
            account: account,
            payoutCycles: viewModel.payoutCyclesForAccountValueSummary(accountID: account.id),
            ledgerEntries: withdrawalsHistory.ledgerByAccount[account.id] ?? [],
            scope: viewModel.clientScopeFilter()
        )
    }

    private var emptyDashboardContent: some View {
        ScrollView(.vertical) {
            VStack(spacing: ExperienceSpacing.lg) {
                dashboardScrollFilterBar
                dashboardOnboardingQuickActionsSection(includeBrokerImport: true)
                ExperienceEmptyState(
                    icon: .chart,
                    title: "No trades yet",
                    message: "Log your first trade to unlock the equity curve and analytics."
                )
                TradingPreferenceDiscoverySlot(
                    surface: .dashboard,
                    userID: discoveryUserID,
                    repository: data?.tradingPreferences,
                    localHasTrade: false,
                    navigationCoordinator: navigationCoordinator
                )
                .padding(.horizontal, ExperienceSpacing.md)
            }
            .padding(.top, ExperienceSpacing.sm)
            .experienceDisablesSystemScrollToTop()
        }
        .dashboardHorizontalLock()
        .scrollPosition(scrollAnchor.binding)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func traxsProPreviewDashboardSections(summary: DashboardChartMetrics.Summary) -> some View {
        sectionHeader(
            DashboardScorecardDisplayCopy.sectionTitle,
            info: "The ring is the overall score for this filter once the sample is large enough. It blends consistency, risk, discipline, and psychology."
        )
        DashboardTradingScorecardSection(showsTitle: false) {
            viewModel.openTradingScorecard()
        }
        .padding(.bottom, ExperienceSpacing.lg)

        DashboardTradingRulesComplianceSection(
            compliancePresentation: premiumAnalyticsPresentation,
            onOpenDetail: { viewModel.openTradingRulesAnalytics() },
            onOpenSettings: { viewModel.openTradingRulesSettings() }
        )
        .padding(.bottom, ExperienceSpacing.xl)

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
            premiumChartsPresentation: premiumAnalyticsPresentation,
            showsStandardCharts: false
        )
        .padding(.bottom, ExperienceSpacing.xl)

        DashboardInsightsSection(presentation: viewModel.insightsPresentation)
            .padding(.bottom, ExperienceSpacing.lg)

        PsychologyInsightsSection(
            title: "Psychology Insights",
            info: Self.psychologyInsightsInfo,
            cards: viewModel.dashboardPsychologyInsightCards,
            unlockProgress: viewModel.psychologyInsightsUnlockProgress,
            insightsReady: viewModel.psychologyInsightsReady,
            unlockMetricsReady: viewModel.psychologyUnlockMetricsReady,
            hasMatchedCheckInDays: viewModel.psychologyHasMatchedCheckInDays,
            postUnlockGapMessages: viewModel.psychologyPostUnlockGapMessages,
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

    @ViewBuilder
    private func productionDashboardSections(summary: DashboardChartMetrics.Summary) -> some View {
        dashboardOnboardingQuickActionsSection(includeBrokerImport: true)

        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            DashboardEquityHero(
                summary: viewModel.equityHeroSummary ?? summary,
                periodTitle: viewModel.dateRange.title,
                title: viewModel.equityHeroTitle,
                displayEquity: viewModel.equityHeroDisplayValue,
                chartPoints: viewModel.equityHeroChartPoints,
                isChartLoading: viewModel.isEquityChartOverlayLoading,
                withdrawalSummary: accountValueWithdrawalSummary,
                onWithdrawalSummaryTap: viewModel.openWithdrawalsHistory,
                showsDrawdownSettings: viewModel.canConfigureEquityDrawdownSettings,
                onDrawdownSettingsTap: viewModel.openEquityDrawdownSettings
            )
            .contextualTourTarget(.dashboardPerformance)

            DashboardMetricStrip(chips: viewModel.metricChips)

            performanceCardsGrid
        }
        .padding(.bottom, ExperienceSpacing.lg)

        if let propStatus = viewModel.propFirmStatus, !restrictsPropFirmMode {
            PropFirmStatusCard(
                snapshot: propStatus,
                onOpenDetails: { viewModel.openPropFirmDetails() }
            )
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.xl)
        }

        sectionHeader(
            DashboardScorecardDisplayCopy.sectionTitle,
            info: "The ring is the overall score for this filter once the sample is large enough. It blends consistency, risk, discipline, and psychology. The lines under it show how often tagged trades followed the plan, how often that held after a loss, and check-ins on trading days."
        )
        DashboardTradingScorecardSection(showsTitle: false) {
            viewModel.openTradingScorecard()
        }
        .padding(.bottom, ExperienceSpacing.lg)

        DashboardTradingRulesComplianceSection(
            compliancePresentation: premiumAnalyticsPresentation,
            onOpenDetail: { viewModel.openTradingRulesAnalytics() },
            onOpenSettings: { viewModel.openTradingRulesSettings() }
        )
        .padding(.bottom, ExperienceSpacing.xl)

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
            premiumChartsPresentation: premiumAnalyticsPresentation
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

        DashboardInsightsSection(presentation: viewModel.insightsPresentation)
            .padding(.bottom, ExperienceSpacing.lg)

        if premiumAnalyticsPresentation == .unrestricted {
            PsychologyInsightsSection(
                title: "Psychology Insights",
                info: Self.psychologyInsightsInfo,
                cards: viewModel.dashboardPsychologyInsightCards,
                unlockProgress: viewModel.psychologyInsightsUnlockProgress,
                insightsReady: viewModel.psychologyInsightsReady,
                unlockMetricsReady: viewModel.psychologyUnlockMetricsReady,
                hasMatchedCheckInDays: viewModel.psychologyHasMatchedCheckInDays,
                postUnlockGapMessages: viewModel.psychologyPostUnlockGapMessages,
                onSelect: { card in
                    viewModel.openPsychologyAnalytics(
                        highlightSection: viewModel.psychologySectionID(for: card.category)
                    )
                },
                onViewAll: {
                    viewModel.openPsychologyAnalytics()
                }
            )
            .padding(.bottom, ExperienceSpacing.lg)
        }

        DashboardTraxProUpsellSection(
            presentation: premiumAnalyticsPresentation,
            profileID: viewModel.ownerAccountsProfileID,
            onRetryEntitlementVerification: refreshDashboardEntitlementIfNeeded
        )
        .padding(.bottom, ExperienceSpacing.xxxl)
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                dashboardScrollFilterBar
                if let summary = viewModel.summary {
                    if embeddedInTraxsProPreview {
                        traxsProPreviewDashboardSections(summary: summary)
                            .padding(.top, ExperienceSpacing.sm)
                    } else {
                        productionDashboardSections(summary: summary)
                    }
                }
            }
            .opacity(contentRevealed || reduceMotion ? 1 : 0.001)
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
                value: contentRevealed
            )
            .onAppear {
                revealContentIfNeeded()
            }
            .experienceDisablesSystemScrollToTop()
        }
        .dashboardHorizontalLock()
        .scrollPosition(scrollAnchor.binding)
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: ContextualTourCoordinator.shared.scrollTarget) { _, target in
            guard let target else { return }
            let anchor = ContextualTourGeometry.scrollAnchor(for: target)
            if reduceMotion {
                proxy.scrollTo(target, anchor: anchor)
            } else {
                withAnimation(ExperienceMotion.navigation) {
                    proxy.scrollTo(target, anchor: anchor)
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

    /// Touches ``WithdrawalsHistoryStore`` so the Payouts card refreshes when ledger/cycles change.
    private var performanceCardsIncludingPayouts: [DashboardMetricChip] {
        viewModel.performanceCards + [
            viewModel.payoutsCardMetricChip(
                withdrawalsHistory: withdrawalsHistory,
                ledgerRowCount: withdrawalsHistory.ledgerEntryCount(),
                completedPropCycleCount: withdrawalsHistory.completedPropCycleCount(),
                achievementPayoutCount: withdrawalsHistory.achievementPayouts.count
            ),
        ]
    }

    private var performanceCardsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: ExperienceSpacing.xs),
                GridItem(.flexible(), spacing: ExperienceSpacing.xs),
            ],
            spacing: ExperienceSpacing.xs
        ) {
            ForEach(performanceCardsIncludingPayouts) { chip in
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
                .experienceDashboardCard(cornerRadius: ExperienceRadius.sm)
                .accessibilityIdentifier("dashboard.card.\(chip.id)")
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private static let psychologyInsightsInfo = "Cards compare trades in this filter with the daily check-in on the same trading day. They cover sleep, mental state, conviction, discipline, emotion, behavior after losses, and how often you trade. A card appears when that comparison has a matched sample."

    private func sectionHeader(_ title: String, info: String) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
                .accessibilityAddTraits(.isHeader)
            AnalyticsMetricInfoButton(
                title: title,
                bodyText: info,
                accessibilityID: "dashboard.sectionInfo.\(DashboardChartInfo.identifier(for: title))"
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.md)
    }

    private var skeleton: some View {
        ScrollView(.vertical) {
        VStack(spacing: ExperienceSpacing.md) {
            dashboardScrollFilterBar
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
        }
        .padding(.top, ExperienceSpacing.sm)
        .experienceDisablesSystemScrollToTop()
        }
        .dashboardHorizontalLock()
        .scrollPosition(scrollAnchor.binding)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("dashboard.skeleton")
        .transition(.opacity)
    }

    private var dashboardPreferenceDiscoverySlot: some View {
        TradingPreferenceDiscoverySlot(
            surface: .dashboard,
            userID: discoveryUserID,
            repository: data?.tradingPreferences,
            localHasTrade: (viewModel.summary?.tradeCount ?? 0) > 0,
            navigationCoordinator: navigationCoordinator
        )
    }

    @ViewBuilder
    private func dashboardOnboardingQuickActionsSection(includeBrokerImport: Bool) -> some View {
        VStack(spacing: ExperienceSpacing.xs) {
            if gettingStartedStore.shouldShowDashboardCard {
                GettingStartedCard(
                    store: gettingStartedStore,
                    navigationCoordinator: navigationCoordinator
                )
            }

            if viewModel.summary != nil {
                dashboardPreferenceDiscoverySlot
            }

            dashboardQuickActionsGroup(includeBrokerImport: includeBrokerImport)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.sm)
    }

    @ViewBuilder
    private func dashboardQuickActionsGroup(includeBrokerImport: Bool) -> some View {
        VStack(spacing: ExperienceSpacing.xs) {
            DailyCheckInCard(store: dailyCheckInStore) {
                ExperienceHaptics.play(.selection)
                navigationCoordinator.present(sheet: .dailyCheckIn)
            }

            if includeBrokerImport, let data {
                DashboardImportTradesSection(
                    data: data,
                    store: brokerImportEligibilityStore,
                    navigationCoordinator: navigationCoordinator
                )
            }
        }
    }

    private func toneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }

    private func preserveScrollOffset() {
        viewModel.rememberScrollOffset(scrollAnchor.offset)
    }

    /// Activity bell, Getting Started, and check-in hydrate after dashboard first paint.
    private func startDeferredDashboardBootstrapIfNeeded() {
        guard viewModel.beginDeferredDashboardBootstrapIfNeeded() else { return }
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

/// The Home tab's `DashboardViewModel` outlives the SwiftUI view.
///
/// `TabView` can destroy the inactive Home root after Feed/Clips. `@State` then
/// evaluates `initialValue` again and used to construct a new model, which
/// cold-loaded, reread GRDB, and rebuilt charts. This store hands that new view
/// the model that already finished loading. Session reset clears the model in
/// place; the next real load is allowed to be cold.
@MainActor
enum DashboardTabModelStore {
    private static var retained: DashboardViewModel?
    private static var retainedScrollAnchor: DashboardScrollAnchor?

    static func model(
        retainsTabPresentation: Bool,
        make: () -> DashboardViewModel
    ) -> DashboardViewModel {
        guard retainsTabPresentation else { return make() }
        if let retained { return retained }
        let created = make()
        retained = created
        return created
    }

    static func scrollAnchor(restoredOffset: CGFloat?) -> DashboardScrollAnchor {
        if let retainedScrollAnchor { return retainedScrollAnchor }
        let created = DashboardScrollAnchor(restoredOffset: restoredOffset)
        retainedScrollAnchor = created
        return created
    }

    static func scrollToTopWhenTabReselectedAtRoot() {
        retained?.scrollToTopForTabReselect()
        retainedScrollAnchor?.resetToTop()
    }

    #if DEBUG
    static func clearForTesting() {
        retained = nil
        retainedScrollAnchor = nil
    }
    #endif
}

/// Holds the dashboard scroll position outside `@Observable` and `@State` writes.
///
/// The scroll view updates this binding as the finger moves. Those writes stay on this
/// object, so the dashboard body does not render again and the restored offset is not
/// reapplied during the gesture. The view model learns the offset only when the tab leaves.
@MainActor
final class DashboardScrollAnchor {
    private var position: ScrollPosition
    private(set) var offset: CGFloat

    init(restoredOffset: CGFloat?) {
        if let restoredOffset {
            position = ScrollPosition(y: restoredOffset)
            offset = restoredOffset
        } else {
            position = ScrollPosition()
            offset = 0
        }
    }

    var binding: Binding<ScrollPosition> {
        Binding(
            get: { self.position },
            set: { newValue in
                let y = newValue.point?.y ?? self.offset
                self.offset = y
                if let x = newValue.point?.x, abs(x) > 0.5 {
                    self.position = ScrollPosition(y: y)
                } else {
                    self.position = newValue
                }
            }
        )
    }

    func resetToTop() {
        position = ScrollPosition()
        offset = 0
    }
}

private extension View {
    /// Keeps dashboard content exactly as wide as the screen so a sideways drag cannot move it.
    func dashboardHorizontalLock() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .containerRelativeFrame(.horizontal, alignment: .leading)
            .clipped()
    }
}

