import SwiftUI

/// Native Backtest Lab — isolated `mode == backtest` journal analytics (web `/backtest` parity).
struct BacktestLabView: View {
    @State private var viewModel: BacktestLabViewModel
    @State private var entitlementGateRevision = 0

    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: BacktestLabViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                tradeDetailRepository: data.tradeDetailRepository,
                navigationCoordinator: navigationCoordinator
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    var body: some View {
        Group {
            if restrictsBacktestLab {
                gatedContent
            } else {
                labContent
            }
        }
        .experienceScreenBackground(usesGroupedFillInLightMode: true)
        .experienceNavigationTitle("Backtest Lab")
        .toolbar(.hidden, for: .tabBar)
        .refreshable {
            guard !restrictsBacktestLab else { return }
            await viewModel.refresh()
        }
        .task(id: restrictsBacktestLab) {
            guard !restrictsBacktestLab else { return }
            viewModel.loadIfNeeded()
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            guard !restrictsBacktestLab else { return }
            Task { await viewModel.refresh() }
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
        .sheet(item: $viewModel.sharePayload) { payload in
            BacktestLabShareSheet(items: [payload.text])
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showsCustomTimeSheet },
            set: { viewModel.showsCustomTimeSheet = $0 }
        )) {
            BacktestLabCustomTimeRangeSheet(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
        .accessibilityIdentifier("backtest.lab.root")
    }

    private var restrictsBacktestLab: Bool {
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

                BacktestLabMetricsGrid(snapshot: viewModel.metrics)
                    .padding(.top, ExperienceSpacing.xxs)

                winsLossesRow
                    .padding(.horizontal, ExperienceSpacing.md)

                strategySection
                    .padding(.horizontal, ExperienceSpacing.md)

                calendarSection
                    .padding(.horizontal, ExperienceSpacing.md)

                tradesSection
                    .padding(.horizontal, ExperienceSpacing.md)
            }
            .padding(.bottom, ExperienceSpacing.xxxl)
        }
    }

    private var upgradeBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("TraxPro Backtest Lab")
                .experienceStyle(.headline, color: colors.primaryText)
            Text("Review backtest performance, calendars, and strategy breakdowns with TraxPro.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                ExperienceHaptics.play(.selection)
                ProUpgradeCoordinator.shared.present(reason: .feature(.backtestLab))
            } label: {
                Text("Upgrade to TraxPro")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("backtest.lab.upgrade")
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .featured)
        .accessibilityIdentifier("backtest.lab.gate")
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
        OwnerAccountFilterDropdown(
            accounts: viewModel.backtestAccountsForMenu,
            isAllAccountsSelected: {
                if case .all = viewModel.accountFilter { return true }
                return false
            }(),
            selectedAccountID: {
                if case .account(let id) = viewModel.accountFilter { return id }
                return nil
            }(),
            onSelectAll: { viewModel.setAccountFilter(.all) },
            onSelectAccount: { viewModel.setAccountFilter(.account($0)) },
            onManageAccounts: { viewModel.openManageAccounts() },
            accessibilityIdentifier: "backtest.lab.account",
            boundary: .trades,
            profileID: viewModel.ownerAccountsProfileID
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

    private var winsLossesRow: some View {
        let snap = viewModel.metrics
        return HStack(spacing: ExperienceSpacing.sm) {
            Text("Wins: \(snap.winCount)")
                .experienceStyle(.footnote, color: colors.profit)
            Text("·")
                .experienceStyle(.footnote, color: colors.tertiaryText)
            Text("Losses: \(snap.lossCount)")
                .experienceStyle(.footnote, color: colors.loss)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.md)
        .experienceTradingRulesCard(prominence: .standard)
    }

    @ViewBuilder
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            backtestSectionHeader("Backtest Calendar")

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                Button {
                    viewModel.shiftCalendarMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.experiencePlain)
                Spacer()
                Text(TradingCalendarDay.monthTitle(
                    year: viewModel.calendarMonth.year,
                    month: viewModel.calendarMonth.month
                ))
                .experienceStyle(.subheadline, color: colors.primaryText)
                Spacer()
                Button {
                    viewModel.shiftCalendarMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.experiencePlain)
            }

            if let month = viewModel.calendarMonthModel {
                CalendarMonthGrid(month: month, selectedDayKey: nil) { _ in }
            } else {
                Text("No backtest activity this month.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, ExperienceSpacing.sm)
            }
            }
            .padding(ExperienceSpacing.md)
            .experienceTradingRulesCard(prominence: .standard)
        }
    }

    private func backtestSectionHeader(_ title: String) -> some View {
        Text(title)
            .experienceStyle(.headline, color: colors.primaryText)
    }

    private var strategyBreakdownGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: ExperienceSpacing.sm),
            GridItem(.flexible(), spacing: ExperienceSpacing.sm),
        ]
    }

    @ViewBuilder
    private var strategySection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            backtestSectionHeader("Strategy Breakdown")

            if viewModel.strategyBreakdown.isEmpty {
                Text("No strategy labels yet. Add a strategy when logging backtest trades.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(ExperienceSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .experienceTradingRulesCard(prominence: .standard)
            } else {
                LazyVGrid(columns: strategyBreakdownGridColumns, spacing: ExperienceSpacing.sm) {
                    ForEach(viewModel.strategyBreakdown) { row in
                        strategyBreakdownCard(row)
                    }
                }
                .accessibilityIdentifier("backtest.lab.strategyBreakdown.grid")
            }
        }
    }

    private func strategyBreakdownCard(_ row: BacktestLabMetrics.StrategyBreakdown) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(row.name)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Trades: \(row.tradeCount)")
                .experienceStyle(.caption, color: colors.secondaryText)
            Text(String(format: "Win rate: %.1f%%", row.winRatePercent))
                .experienceStyle(.caption, color: colors.secondaryText)
            Text("P&L: \(TradeDisplay.pnlText(Money(amount: row.totalPnL)))")
                .experienceStyle(.caption, color: theme.metricColor(
                    for: NSDecimalNumber(decimal: row.totalPnL).doubleValue
                ))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let rr = row.averageRR {
                Text("Avg R:R: \(TradeDisplay.compactRRText(Decimal(rr)) ?? "—")")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .experienceTradingRulesCard(cornerRadius: ExperienceRadius.md)
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
                        onShare: { viewModel.shareTrade(item) },
                        onEdit: { viewModel.editTrade(item) },
                        onDelete: { viewModel.requestDelete(item) }
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
