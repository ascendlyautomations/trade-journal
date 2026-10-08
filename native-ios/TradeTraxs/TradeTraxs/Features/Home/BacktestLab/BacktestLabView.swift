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
        .experienceScreenBackground()
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
                Task { await viewModel.confirmDelete() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDelete = nil
            }
        }
        .sheet(item: $viewModel.sharePayload) { payload in
            BacktestLabShareSheet(items: [payload.text])
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
                introCopy
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.sm)
                upgradeBlock
                    .padding(.horizontal, ExperienceSpacing.md)
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
                introCopy
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.sm)

                strategyRow
                    .padding(.horizontal, ExperienceSpacing.md)

                metricStrip
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

    private var introCopy: some View {
        Text("Backtest trades stay separate from dashboard, Trades history, and performance analytics.")
            .experienceStyle(.footnote, color: colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
        .accessibilityIdentifier("backtest.lab.gate")
    }

    private var strategyRow: some View {
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
            HStack(spacing: 4) {
                Text(viewModel.strategyMenuTitle)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .lineLimit(1)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.secondaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .background(colors.fillSecondary, in: Capsule())
        }
        .accessibilityIdentifier("backtest.lab.strategy")
    }

    private var metricStrip: some View {
        let snap = viewModel.metrics
        let pnlTone: DashboardMetricTone = {
            if snap.totalPnL > 0 { return .positive }
            if snap.totalPnL < 0 { return .negative }
            return .neutral
        }()
        return DashboardMetricStrip(chips: [
            DashboardMetricChip(
                id: "trades",
                label: "Trades",
                value: "\(snap.tradeCount)",
                tone: .neutral
            ),
            DashboardMetricChip(
                id: "winRate",
                label: "Win Rate",
                value: String(format: "%.1f%%", snap.winRatePercent),
                tone: .neutral
            ),
            DashboardMetricChip(
                id: "pnl",
                label: "Total PnL",
                value: TradeDisplay.pnlText(Money(amount: snap.totalPnL)),
                tone: pnlTone
            ),
            DashboardMetricChip(
                id: "avgRR",
                label: "Avg RR",
                value: snap.averageRR.map { TradeDisplay.compactRRText(Decimal($0)) ?? "—" } ?? "—",
                tone: .neutral
            ),
        ])
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
        .padding(ExperienceSpacing.sm)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
    }

    @ViewBuilder
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Backtest Calendar")
                .experienceStyle(.headline, color: colors.primaryText)

            HStack {
                Button {
                    viewModel.shiftCalendarMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
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
                .buttonStyle(.plain)
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
            Text("Strategy Breakdown")
                .experienceStyle(.headline, color: colors.primaryText)

            if viewModel.strategyBreakdown.isEmpty {
                Text("No strategy labels yet. Add a strategy when logging backtest trades.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
        ExperienceCard {
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
                Text("PnL: \(TradeDisplay.pnlText(Money(amount: row.totalPnL)))")
                    .experienceStyle(.caption, color: theme.metricColor(
                        for: NSDecimalNumber(decimal: row.totalPnL).doubleValue
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let rr = row.averageRR {
                    Text("Avg RR: \(TradeDisplay.compactRRText(Decimal(rr)) ?? "—")")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Backtest Trades")
                .experienceStyle(.headline, color: colors.primaryText)

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
