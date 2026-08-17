import SwiftUI

struct TradingDayDetailView: View {
    let dayKey: String
    @State private var viewModel: CalendarDayDetailLoader
    private let imagePipeline: any ImagePipeline
    private let engagementStore: EngagementStore
    private let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    init(dayKey: String, data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        self.dayKey = dayKey
        _viewModel = State(
            initialValue: CalendarDayDetailLoader(
                dayKey: dayKey,
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache
            )
        )
        self.imagePipeline = data.imagePipeline
        self.engagementStore = data.engagementStore
        self.navigationCoordinator = navigationCoordinator
    }

    init(
        dayKey: String,
        viewModel: CalendarDayDetailLoader,
        imagePipeline: any ImagePipeline,
        engagementStore: EngagementStore,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.dayKey = dayKey
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
        self.engagementStore = engagementStore
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
        .accessibilityIdentifier("calendar.tradingDay")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Net P&L")
                .experienceStyle(.footnote, color: colors.secondaryText)
            Text(CalendarFormatting.fullPnL(viewModel.summary?.netPnL ?? 0))
                .experienceStyle(
                    .metricLarge,
                    color: theme.metricColor(
                        for: NSDecimalNumber(decimal: viewModel.summary?.netPnL ?? 0).doubleValue
                    )
                )
            if let summary = viewModel.summary {
                Text(CalendarFormatting.tradeCount(summary.tradeCount))
                    .experienceStyle(.subheadline, color: colors.secondaryText)
            } else if !viewModel.isLoading {
                Text("No trades")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
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
                    if let rate = summary.winRate {
                        metricCard("Win rate", ProfileDisplay.formatWinRate(rate))
                    }
                    metricCard("Gross profit", CalendarFormatting.fullPnL(summary.grossProfit))
                    metricCard("Gross loss", CalendarFormatting.fullPnL(summary.grossLoss))
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
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }

    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Trades")
                .experienceStyle(.headline, color: colors.primaryText)

            if viewModel.dayTrades.isEmpty, !viewModel.isLoading {
                if let error = viewModel.errorMessage {
                    ExperienceErrorState(
                        title: "Couldn't load trades",
                        message: error,
                        onRetry: { viewModel.loadIfNeeded(force: true) }
                    )
                } else {
                    Text("No trades on this day.")
                        .experienceStyle(.body, color: colors.secondaryText)
                }
            } else {
                ForEach(viewModel.dayTrades) { trade in
                    ProfileTradeCard(
                        trade: trade,
                        accountName: viewModel.displayAccountTitle(for: trade.accountID),
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        showsOwnerActions: false,
                        onOpen: {
                            viewModel.openTrade(trade, navigation: navigationCoordinator)
                        },
                        onShare: {},
                        onEdit: {},
                        onDelete: {}
                    )
                }
            }
        }
    }
}

/// Self-contained day detail loader (does not require CalendarViewModel instance).
@Observable
@MainActor
final class CalendarDayDetailLoader {
    let dayKey: String
    private(set) var summary: TradingDaySummary?
    private(set) var dayTrades: [Trade] = []
    private(set) var accountNames: [TradingAccountID: String] = [:]
    private var accounts: [TradingAccount] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private var hasLoaded = false

    init(
        dayKey: String,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache
    ) {
        self.dayKey = dayKey
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
    }

    func displayAccountTitle(for accountID: TradingAccountID?) -> String? {
        guard let accountID else { return nil }
        if let account = accounts.first(where: { $0.id == accountID }) {
            return TradingAccountDisplay.optionalTitle(
                name: account.name,
                accountNumber: account.accountNumber,
                audience: .owner
            )
        }
        return TradingAccountDisplay.optionalTitle(
            name: accountNames[accountID],
            audience: .owner
        )
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await refresh() }
    }

    func loadIfNeeded(force: Bool) {
        if force {
            hasLoaded = false
            errorMessage = nil
        }
        loadIfNeeded()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let userID = await session.currentUserID
        let profileID = ProfileID(userID?.rawValue ?? "dev.screenshot")

        if let loaded = SessionAccountsStore.shared.cached(for: profileID)
            ?? detailCache.accounts(for: profileID)
        {
            applyAccounts(loaded)
        }

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            let all = CalendarFixtures.trades(owner: profileID)
            apply(all)
            return
        }

        guard let comps = TradingCalendarDay.components(from: dayKey),
              let window = TradingCalendarDay.fetchWindow(year: comps.year, month: comps.month)
        else {
            errorMessage = "Invalid day"
            return
        }

        do {
            if accounts.isEmpty {
                let loaded = try await SessionAccountsStore.shared.accounts(
                    for: profileID,
                    detailCache: detailCache,
                    repository: trades
                )
                applyAccounts(loaded)
            }

            // Day detail is a reader of the month session cache owned by Calendar home.
            // Prefer any cached month window — do not require freshness (avoids a second SELECT).
            if let cachedMonth = CalendarMonthSessionStore.shared.trades(
                year: comps.year,
                month: comps.month
            ) {
                SessionNetworkProbe.record(
                    .cacheHit,
                    resource: "calendar.day.month",
                    detail: dayKey
                )
                apply(cachedMonth)
                return
            }

            SessionNetworkProbe.record(
                .networkFetch,
                resource: "calendar.day.month",
                detail: dayKey
            )
            let fetched = try await trades.trades(
                ownedBy: profileID,
                accountID: nil,
                entryFrom: window.start,
                entryTo: window.end,
                limit: 500
            )
            CalendarMonthSessionStore.shared.store(fetched, year: comps.year, month: comps.month)
            detailCache.seed(trades: fetched)
            apply(fetched)
        } catch {
            // Fall back to any seeded trades in detail cache window.
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func openTrade(_ trade: Trade, navigation: NavigationCoordinator) {
        detailCache.seed(trade)
        navigation.open(.home(.tradeDetail(trade.id)))
    }

    private func applyAccounts(_ loaded: [TradingAccount]) {
        accounts = loaded
        accountNames = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.name) })
    }

    private func apply(_ trades: [Trade]) {
        dayTrades = TradingCalendarAggregator.trades(
            for: dayKey,
            from: trades,
            accountFilter: .all
        )
        summary = TradingCalendarAggregator.daySummaries(
            from: trades,
            accountFilter: .all
        )[dayKey]
    }
}
