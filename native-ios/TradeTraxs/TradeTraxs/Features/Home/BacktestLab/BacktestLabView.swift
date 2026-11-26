import SwiftUI

/// Native Backtest Lab, isolated `mode == backtest` journal analytics (web `/backtest` parity).
struct BacktestLabView: View {
    @State private var viewModel: BacktestLabViewModel
    @State private var entitlementGateRevision = 0

    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment
    private let embeddedInTraxsProPreview: Bool

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme
    @Environment(\.traxsProPreviewReadOnly) private var traxsProPreviewReadOnly

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        embeddedInTraxsProPreview: Bool = false
    ) {
        self.embeddedInTraxsProPreview = embeddedInTraxsProPreview
        _viewModel = State(
            initialValue: BacktestLabViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                tradeDetailRepository: data.tradeDetailRepository,
                navigationCoordinator: navigationCoordinator,
                loadsTraxsProPreviewSampleOnly: embeddedInTraxsProPreview
            )
        )
        self.imagePipeline = data.imagePipeline
        self.data = data
    }

    private var isPreviewReadOnly: Bool {
        embeddedInTraxsProPreview || traxsProPreviewReadOnly
    }

    var body: some View {
        Group {
            if showsEntitlementVerification {
                TraxProEntitlementVerificationView(profileID: viewerProfileID) {
                    Task { await TraxProEntitlementRefreshAction.refresh(data: data) }
                }
            } else if restrictsBacktestLab {
                gatedContent
            } else {
                labContent
            }
        }
        .experienceScreenBackground(usesGroupedFillInLightMode: true)
        .experienceNavigationTitle("Backtest Lab")
        .toolbar {
            if !restrictsBacktestLab, !showsEntitlementVerification {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.openCalendar()
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Backtest Calendar")
                    .accessibilityIdentifier("backtest.lab.calendar")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .refreshable {
            guard !restrictsBacktestLab else { return }
            await viewModel.refresh()
        }
        .task(id: restrictsBacktestLab) {
            guard !restrictsBacktestLab, !showsEntitlementVerification else { return }
            viewModel.loadIfNeeded()
        }
        .task(id: showsEntitlementVerification) {
            if showsEntitlementVerification {
                await TraxProEntitlementRefreshAction.refresh(data: data)
            }
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            guard !restrictsBacktestLab else { return }
            Task { await viewModel.refresh() }
        }
        .onOwnerAccountMutation {
            guard !restrictsBacktestLab else { return }
            viewModel.handleAccountMutation()
        }
        .onCopyTradingGroupsMutation {
            guard !restrictsBacktestLab else { return }
            viewModel.handleCopyTradingGroupsMutation()
        }
        .confirmationDialog(
            "Delete this backtest?",
            isPresented: Binding(
                get: { viewModel.pendingDelete != nil },
                set: { if !$0 { viewModel.pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Trade", role: .destructive) {
                let item = viewModel.pendingDelete
                Task { await viewModel.confirmDelete(item: item) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDelete = nil
            }
        }
        .sheet(item: $viewModel.journalSharePresentation) { presentation in
            SharedContentShareSheet(
                target: presentation.target,
                data: data,
                tradeOwnerShareAccess: presentation.ownerAccess,
                onClose: { viewModel.journalSharePresentation = nil }
            )
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showsCustomTimeSheet },
            set: { viewModel.showsCustomTimeSheet = $0 }
        )) {
            BacktestLabCustomTimeRangeSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showsEquityDrawdownSettings) {
            if let account = viewModel.selectedAccount {
                DashboardEquityDrawdownSettingsSheet(
                    accountName: account.name,
                    limitDigits: $viewModel.equityDrawdownLimitDraft,
                    limitType: $viewModel.equityDrawdownTypeDraft,
                    floorCapDigits: $viewModel.equityDrawdownFloorCapDraft,
                    isSaving: viewModel.isSavingEquityDrawdownSettings,
                    errorMessage: viewModel.equityDrawdownSettingsError,
                    onSave: { Task { await viewModel.saveEquityDrawdownSettings() } },
                    onCancel: viewModel.cancelEquityDrawdownSettings
                )
            }
        }
        .sheet(item: $viewModel.activeDrillDown) { drillDown in
            BacktestLabDrillDownSheet(
                title: drillDown.title,
                items: viewModel.drillDownJournalItems,
                imagePipeline: imagePipeline,
                accountName: { viewModel.displayAccountTitle(for: $0) },
                onSelect: { viewModel.openTrade($0) },
                onDismiss: { viewModel.dismissDrillDown() }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
        .accessibilityIdentifier("backtest.lab.root")
    }

    private var showsEntitlementVerification: Bool {
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldShowEntitlementVerification(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: viewerProfileID
        )
    }

    private var restrictsBacktestLab: Bool {
        if embeddedInTraxsProPreview { return false }
        _ = entitlementGateRevision
        return ProMonetizationPolicy.shouldRestrictBacktestLab(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: viewerProfileID
        )
    }

    private var viewerProfileID: ProfileID? {
        guard let bootstrap = SessionBootstrapStore.shared.last else { return nil }
        return ProfileID(bootstrap.data.viewer.id)
    }

    private var gatedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                upgradeBlock
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
    }

    private var labContent: some View {
        Group {
            switch viewModel.phase {
            case .idle:
                ExperienceListSkeleton(style: .tradeCard, rowCount: 3)
            case .loading where viewModel.allTrades.isEmpty:
                ExperienceListSkeleton(style: .tradeCard, rowCount: 3)
            case .loading:
                labScrollContent
            case .failed(let message) where viewModel.allTrades.isEmpty:
                ExperienceErrorState(
                    title: "Couldn't load Backtest Lab",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            case .failed:
                labScrollContent
            case .loaded:
                labScrollContent
            }
        }
    }

    private var labScrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                filterBar
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)

                if let summary = viewModel.dashboardSummary,
                   summary.tradeCount > 0 || !viewModel.equityChartPoints.isEmpty
                {
                    dashboardAnalyticsContent(summary: summary)
                } else if viewModel.filteredTrades.isEmpty {
                    emptyAnalyticsPlaceholder
                } else {
                    ExperienceListSkeleton(style: .tradeCard, rowCount: 2)
                }

                tradesSection
                    .padding(.horizontal, ExperienceSpacing.md)
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
    }

  @ViewBuilder
    private func dashboardAnalyticsContent(summary: DashboardChartMetrics.Summary) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            DashboardEquityHero(
                summary: summary,
                periodTitle: viewModel.timeMenuTitle,
                title: viewModel.equityHeroTitle,
                displayEquity: viewModel.equityHeroDisplayValue,
                chartPoints: viewModel.equityChartPoints,
                showsDrawdownSettings: viewModel.canConfigureEquityDrawdownSettings,
                onDrawdownSettingsTap: { viewModel.openEquityDrawdownSettings() }
            )

            DashboardMetricStrip(chips: viewModel.metricChips)
                .padding(.horizontal, ExperienceSpacing.md)

            backtestPerformanceCardsGrid
                .padding(.horizontal, ExperienceSpacing.md)

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
                premiumChartsPresentation: .unrestricted
            )

            DashboardInsightsSection(presentation: viewModel.insightsPresentation)

            BacktestLabLeaderboardSection(
                title: "Strategy Performance",
                rows: viewModel.strategyLeaderboard,
                onSelect: { viewModel.browseStrategy(key: $0.key) }
            )
            .padding(.horizontal, ExperienceSpacing.md)

            BacktestLabLeaderboardSection(
                title: "Setup Tag Performance",
                rows: viewModel.setupTagLeaderboard,
                onSelect: { viewModel.browseSetupTag(key: $0.key) }
            )
            .padding(.horizontal, ExperienceSpacing.md)

            BacktestLabLeaderboardSection(
                title: "Instrument Performance",
                rows: viewModel.instrumentLeaderboard,
                onSelect: { viewModel.browseInstrument(key: $0.key) }
            )
            .padding(.horizontal, ExperienceSpacing.md)
        }
    }

    private var emptyAnalyticsPlaceholder: some View {
        ExperienceEmptyState(
            icon: .chart,
            title: "No backtest trades",
            message: "Log trades on a Backtest account for strategy analytics."
        )
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private var backtestPerformanceCardsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: ExperienceSpacing.xs),
                GridItem(.flexible(), spacing: ExperienceSpacing.xs),
            ],
            spacing: ExperienceSpacing.xs
        ) {
            ForEach(viewModel.performanceCards) { chip in
                VStack(alignment: .leading, spacing: 4) {
                    Text(chip.label)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text(chip.value)
                        .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(backtestToneColor(chip.tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .experienceDashboardCard(cornerRadius: ExperienceRadius.sm)
                .accessibilityIdentifier("backtest.lab.card.\(chip.id)")
            }
        }
    }

    private func backtestToneColor(_ tone: DashboardMetricTone) -> Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }

    private var upgradeBlock: some View {
        TraxProFeaturePreviewCard(
            title: MonetizationPlanCopy.backtestLabFeatureGateTitle,
            message: MonetizationPlanCopy.backtestLabFeatureGateMessage,
            feature: .backtestLab,
            previewEntryPoint: .backtestLabGate,
            accessibilityIdentifier: "backtest.lab.gate"
        )
    }

    private var filterBar: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            accountFilterMenu
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            strategyFilterMenu
            timeFilterMenu
        }
        .accessibilityIdentifier("backtest.lab.filters")
    }

    private var accountFilterMenu: some View {
        let profileID = viewModel.ownerAccountsProfileID
        return OwnerAccountFilterDropdown(
            accounts: viewModel.backtestAccountsForMenu,
            selectedFilter: viewModel.accountFilter,
            copyGroups: [],
            isLoadingCopyGroups: false,
            onSelectFilter: { viewModel.setAccountFilter($0) },
            onManageAccounts: { viewModel.openManageAccounts() },
            onManageCopyGroups: {},
            onRequestCopyGroups: {},
            accessibilityIdentifier: "backtest.lab.account",
            includesCopyTradingMenu: false,
            boundary: .trades,
            profileID: profileID
        ) {
            filterCapsuleLabel(viewModel.accountMenuTitle)
        }
        .accessibilityLabel("Account")
        .accessibilityValue(viewModel.accountMenuTitle)
    }

    private var strategyFilterMenu: some View {
        Menu {
            ForEach(viewModel.strategyOptions, id: \.self) { option in
                Button {
                    viewModel.setStrategy(option)
                } label: {
                    if option == BacktestLabMetrics.allStrategiesToken {
                        Text("All Strategies")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            filterCapsuleLabel(viewModel.strategyMenuTitle)
        }
        .accessibilityIdentifier("backtest.lab.strategy")
    }

    private var timeFilterMenu: some View {
        Menu {
            ForEach(BacktestLabTimeFilter.allCases) { option in
                Button {
                    viewModel.setTimeFilter(option)
                } label: {
                    Text(option.menuTitle)
                }
            }
        } label: {
            filterCapsuleLabel(viewModel.timeMenuTitle)
        }
        .accessibilityLabel("Time")
        .accessibilityValue(viewModel.timeMenuTitle)
        .accessibilityIdentifier("backtest.lab.time")
    }

    private func filterCapsuleLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .experienceStyle(.footnote, color: colors.primaryText)
                .lineLimit(1)
            ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .frame(minHeight: 32)
        .tradingRulesFilterChip()
        .experienceControlHitTarget()
    }

    private func backtestSectionHeader(_ title: String) -> some View {
        Text(title)
            .experienceStyle(.headline, color: colors.primaryText)
    }

    @ViewBuilder
    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            backtestSectionHeader("Backtest Trades")

            if viewModel.journalItems.isEmpty {
                ExperienceEmptyState(
                    icon: .trades,
                    title: "No backtest trades",
                    message: "Log trades on a Backtest account to see them here.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                ForEach(viewModel.journalItems) { item in
                    TradeJournalCard(
                        item: item,
                        accountName: viewModel.displayAccountTitle(for: item.accountID),
                        imagePipeline: imagePipeline,
                        onOpen: { viewModel.openTrade(item) },
                        onShare: isPreviewReadOnly ? nil : { viewModel.shareTrade(item) },
                        onEdit: isPreviewReadOnly ? nil : { viewModel.editTrade(item) },
                        onDelete: isPreviewReadOnly ? nil : { viewModel.requestDelete(item) }
                    )
                }
            }
        }
    }
}

private struct BacktestLabShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
