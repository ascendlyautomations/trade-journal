import SwiftUI

/// Trading day detail for backtest calendar taps (owner journal cards).
struct BacktestTradingDayDetailView: View {
    let dayKey: String
    @State private var viewModel: BacktestTradingDayDetailLoader

    private let imagePipeline: any ImagePipeline
    private let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    init(
        dayKey: String,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        embeddedInTraxsProPreview: Bool = false
    ) {
        self.dayKey = dayKey
        _viewModel = State(
            initialValue: BacktestTradingDayDetailLoader(
                dayKey: dayKey,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                loadsTraxsProPreviewSampleOnly: embeddedInTraxsProPreview
            )
        )
        self.imagePipeline = data.imagePipeline
        self.navigationCoordinator = navigationCoordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                hero
                metrics
                tradesSection
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.md)
            .padding(.bottom, ExperienceSpacing.xl)
        }
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle(TradingCalendarDay.displayDate(from: dayKey))
        .overlay {
            if viewModel.isLoading && viewModel.summary == nil {
                ProgressView()
            }
        }
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityIdentifier("backtest.calendar.tradingDay")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            heroTitleLine
            Text(CalendarFormatting.fullPnL(viewModel.summary?.netPnL ?? 0))
                .experienceStyle(
                    .metricLarge,
                    color: theme.metricColor(
                        for: NSDecimalNumber(decimal: viewModel.summary?.netPnL ?? 0).doubleValue
                    )
                )
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceGroupedPanel(cornerRadius: ExperienceRadius.lg)
    }

    @ViewBuilder
    private var heroTitleLine: some View {
        HStack(spacing: 6) {
            Text("Net P&L")
                .fontWeight(.semibold)
            Text("|")
            if let summary = viewModel.summary {
                Text(CalendarFormatting.tradeCount(summary.tradeCount))
            } else if !viewModel.isLoading {
                Text("No trades")
            } else {
                Text("–")
            }
        }
        .font(ExperienceTypography.font(.footnote))
        .foregroundStyle(colors.secondaryText)
    }

    private var metrics: some View {
        Group {
            if let summary = viewModel.summary {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: ExperienceSpacing.sm
                ) {
                    metricCard("Wins", "\(summary.winCount)")
                    metricCard("Losses", "\(summary.lossCount)")
                    metricCard("Gross Profit", CalendarFormatting.fullPnL(summary.grossProfit))
                    metricCard("Gross Loss", CalendarFormatting.fullPnL(summary.grossLoss))
                    metricCard("Win Rate", NumberDisplay.winRate(summary.winRate))
                    metricCard(
                        "Avg R:R",
                        viewModel.averageTargetedRr.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "–"
                    )
                }
            }
        }
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .experienceStyle(.caption, color: colors.secondaryText)
            Text(value)
                .experienceStyle(.headline, color: colors.primaryText)
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.md)
    }

    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Trades")
                .experienceStyle(.headline, color: colors.primaryText)

            if viewModel.journalItems.isEmpty, !viewModel.isLoading {
                if let error = viewModel.errorMessage {
                    ExperienceErrorState(
                        title: "Couldn't load trades",
                        message: error,
                        onRetry: { viewModel.loadIfNeeded(force: true) }
                    )
                } else {
                    Text("No backtest trades on this day.")
                        .experienceStyle(.body, color: colors.secondaryText)
                }
            } else {
                ForEach(viewModel.journalItems) { item in
                    TradeJournalCard(
                        item: item,
                        accountName: viewModel.displayAccountTitle(for: item.accountID),
                        imagePipeline: imagePipeline,
                        onOpen: { viewModel.openTrade(item, navigation: navigationCoordinator) }
                    )
                }
            }
        }
    }
}

@Observable
@MainActor
final class BacktestTradingDayDetailLoader {
    let dayKey: String

    private(set) var summary: TradingDaySummary?
    private(set) var journalItems: [TradeOwnerJournalSummary] = []
    private var dayTrades: [Trade] = []
    private(set) var accountNames: [TradingAccountID: String] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let loadsTraxsProPreviewSampleOnly: Bool
    private var hasLoaded = false

    init(
        dayKey: String,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        loadsTraxsProPreviewSampleOnly: Bool = false
    ) {
        self.dayKey = dayKey
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.loadsTraxsProPreviewSampleOnly = loadsTraxsProPreviewSampleOnly
    }

    var averageTargetedRr: Decimal? {
        TradePointsAndRealizedRr.averageTargetedRr(trades: dayTrades)
    }

    func displayAccountTitle(for accountID: TradingAccountID?) -> String? {
        guard let accountID else { return nil }
        return accountNames[accountID]
    }

    func loadIfNeeded(force: Bool = false) {
        guard force || !hasLoaded else { return }
        Task { await performLoad() }
    }

    func openTrade(_ item: TradeOwnerJournalSummary, navigation: NavigationCoordinator) {
        ExperienceHaptics.play(.selection)
        detailCache.seedPresentationSeed(TradeSummaryMapper.presentationSeed(from: item))
        if let accountID = item.accountID, let name = accountNames[accountID] {
            detailCache.seedAccountName(name, for: accountID)
        }
        navigation.open(.home(.tradeDetail(item.id)))
    }

    private func performLoad() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false; hasLoaded = true }
        do {
            guard let viewer = await session.currentUserID else {
                errorMessage = "Sign in to view this day."
                return
            }
            let profileID = ProfileID(viewer.rawValue)
            let all: [Trade]
            let accounts: [TradingAccount]
            if loadsTraxsProPreviewSampleOnly {
                all = BacktestLabPreviewSampleData.trades(owner: profileID)
                accounts = BacktestLabPreviewSampleData.accounts(owner: profileID)
            } else {
                all = try await trades.backtestLabTrades(ownedBy: profileID)
                accounts = try await trades.accounts(for: profileID)
            }
            accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })

            let filtered = BacktestCalendarSessionStore.shared.filteredTrades(from: all, accounts: accounts)
            let matched = BacktestLabCalendarSupport.trades(for: dayKey, from: filtered)
            dayTrades = matched
            journalItems = matched.map(TradeSummaryMapper.ownerJournal(fromListTrade:))
            for item in journalItems {
                detailCache.seedPresentationSeed(TradeSummaryMapper.presentationSeed(from: item))
            }
            summary = BacktestLabCalendarSupport.daySummaries(from: dayTrades)[dayKey]
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}