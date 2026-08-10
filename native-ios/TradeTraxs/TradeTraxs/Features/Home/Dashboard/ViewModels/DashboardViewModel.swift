import Foundation
import Observation

/// Home Dashboard — session-cached trades → presentation metrics → idle.
///
/// Load path: Initial Load → Session Cache → Repository → Realtime subscribe → Idle.
/// Filter changes recompute locally; pull-to-refresh is the only forced refetch.
@Observable
@MainActor
final class DashboardViewModel {
    private(set) var phase: DashboardLoadPhase = .idle
    private(set) var summary: DashboardChartMetrics.Summary?
    private(set) var accounts: [TradingAccount] = []
    private(set) var recentTrades: [Trade] = []
    private(set) var accountNames: [TradingAccountID: String] = [:]
    private(set) var isRefreshing = false

    var accountFilter: DashboardAccountFilter = .all
    var dateRange: DashboardDateRange = .thirtyDays

    private let home: any HomeRepository
    private let trades: any TradeRepository
    private let achievements: any AchievementRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let realtimeHub: RealtimeHub?

    private var profileID: ProfileID?
    private var tradeInputs: [DashboardChartMetrics.Input] = []
    private var payoutTotal: Decimal?
    private var loadTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var hasLoaded = false
    private var watchedChannel: RealtimeChannelID?

    init(
        home: any HomeRepository,
        trades: any TradeRepository,
        achievements: any AchievementRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        realtimeHub: RealtimeHub? = nil
    ) {
        self.home = home
        self.trades = trades
        self.achievements = achievements
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.realtimeHub = realtimeHub
    }

    var accountFilterTitle: String {
        switch accountFilter {
        case .all:
            return "All Accounts"
        case .account(let id):
            return accountNames[id] ?? "Account"
        }
    }

    var metricChips: [DashboardMetricChip] {
        guard let summary else { return [] }
        return [
            DashboardMetricChip(
                id: "net",
                label: "Net P&L",
                value: Self.money(summary.netPnL),
                tone: summary.netPnL >= 0 ? .positive : .negative
            ),
            DashboardMetricChip(
                id: "win",
                label: "Win %",
                value: ProfileDisplay.formatWinRate(summary.winRate),
                tone: .neutral
            ),
            DashboardMetricChip(
                id: "pf",
                label: "Profit Factor",
                value: Self.factor(summary.profitFactor),
                tone: {
                    guard let pf = summary.profitFactor else { return .neutral }
                    return pf >= 1 ? .positive : .negative
                }()
            ),
            DashboardMetricChip(
                id: "payouts",
                label: "Payouts",
                value: ProfileDisplay.formatMoney(summary.payouts),
                tone: (summary.payouts ?? 0) > 0 ? .positive : .neutral
            ),
            DashboardMetricChip(
                id: "expectancy",
                label: "Expectancy",
                value: summary.expectancy.map(Self.money) ?? "—",
                tone: {
                    guard let e = summary.expectancy else { return .neutral }
                    return e >= 0 ? .positive : .negative
                }()
            ),
            DashboardMetricChip(
                id: "rr",
                label: "Avg RR",
                value: summary.averageRR.map { String(format: "%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "—",
                tone: .neutral
            ),
        ]
    }

    /// Present only when a single prop-firm account is selected.
    var propFirmStatus: PropFirmStatusSnapshot? {
        guard case .account(let id) = accountFilter,
              let account = accounts.first(where: { $0.id == id }),
              account.isPropFirmAccount
        else { return nil }
        let trades = tradeInputs.map(\.trade)
        return PropFirmStatusSnapshot.build(account: account, trades: trades)
    }

    func accountMenuTitle(for account: TradingAccount) -> String {
        if account.isPropFirmAccount {
            let size = account.size.map { DashboardViewModel.compactSize($0.amount) }
            if let size {
                return "\(account.name) \(size)  PROP"
            }
            return "\(account.name)  PROP"
        }
        return account.name
    }

    func openPropFirmDetails() {
        guard case .account(let id) = accountFilter else { return }
        navigationCoordinator.open(.home(.propFirm(id)))
    }

    var performanceCards: [DashboardMetricChip] {
        guard let summary else { return [] }
        return [
            DashboardMetricChip(
                id: "trades",
                label: "Trades",
                value: "\(summary.tradeCount)",
                tone: .neutral
            ),
            DashboardMetricChip(
                id: "avgWin",
                label: "Avg Win",
                value: summary.avgWin.map(Self.money) ?? "—",
                tone: .positive
            ),
            DashboardMetricChip(
                id: "avgLoss",
                label: "Avg Loss",
                value: summary.avgLoss.map(Self.money) ?? "—",
                tone: .negative
            ),
            DashboardMetricChip(
                id: "best",
                label: "Best Trade",
                value: summary.bestTrade.map(Self.money) ?? "—",
                tone: .positive
            ),
            DashboardMetricChip(
                id: "worst",
                label: "Biggest Loss",
                value: summary.biggestLoss.map(Self.money) ?? "—",
                tone: .negative
            ),
            DashboardMetricChip(
                id: "dd",
                label: "Max Drawdown",
                value: Self.money(summary.maxDrawdown),
                tone: summary.maxDrawdown > 0 ? .negative : .neutral
            ),
        ]
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        isRefreshing = true
        await performLoad(forceNetwork: true)
        isRefreshing = false
    }

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        guard accountFilter != filter else { return }
        ExperienceHaptics.play(.selection)
        accountFilter = filter
        recompute()
    }

    func setDateRange(_ range: DashboardDateRange) {
        guard dateRange != range else { return }
        ExperienceHaptics.play(.selection)
        dateRange = range
        recompute()
    }

    func openCalendar() {
        navigationCoordinator.open(.home(.calendar))
    }

    func openTrade(_ trade: Trade) {
        detailCache.seed(trade)
        navigationCoordinator.open(.home(.tradeDetail(trade.id)))
    }

    func openTradesList() {
        navigationCoordinator.open(.home(.trades))
    }

    func onDisappear() {
        Task { await stopRealtime() }
    }

    // MARK: - Load

    private func performLoad(forceNetwork: Bool = false) async {
        let userID = await session.currentUserID
        let profileID = ProfileID(userID?.rawValue ?? "dev.screenshot")
        self.profileID = profileID

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            applyFixtures(profileID: profileID)
            hasLoaded = true
            phase = .loaded
            await startRealtime(profileID: profileID)
            loadTask = nil
            return
        }

        if summary == nil { phase = .loading }

        do {
            // Session cache — recompute only; never refetch analytics on filter changes.
            if !forceNetwork, hasLoaded, !tradeInputs.isEmpty {
                recompute()
                phase = .loaded
                loadTask = nil
                return
            }

            async let tradesTask = trades.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(limit: 500),
                publicOnly: false
            )
            async let accountsTask = trades.accounts(for: profileID)
            async let achievementsTask = achievements.achievements(
                for: profileID,
                page: PageRequest(limit: 500),
                publicOnly: true
            )
            // Warm HomeRepository summary (streak / interval) without driving UI math.
            async let homeTask = home.dashboard(for: profileID)

            let page = try await tradesTask
            let fetchedAccounts: [TradingAccount]
            if let cachedAccounts = detailCache.accounts(for: profileID), !forceNetwork {
                fetchedAccounts = cachedAccounts
            } else {
                fetchedAccounts = (try? await accountsTask) ?? []
                detailCache.seed(accounts: fetchedAccounts, for: profileID)
            }
            detailCache.seed(trades: page.items)

            if let achievementPage = try? await achievementsTask {
                detailCache.seed(achievements: achievementPage.items)
                payoutTotal = ProfilePayoutTotals.sum(from: achievementPage.items)
            } else if let stats = detailCache.stats(for: profileID) {
                payoutTotal = stats.payoutTotal
            }
            _ = try? await homeTask

            apply(trades: page.items, accounts: fetchedAccounts, profileID: profileID)

            guard !Task.isCancelled else { return }
            hasLoaded = true
            recompute()
            phase = .loaded
            await startRealtime(profileID: profileID)
        } catch {
            guard !Task.isCancelled else { return }
            if summary == nil {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func applyFixtures(profileID: ProfileID) {
        let samples = ProfileTradeFixtures.samples(owner: profileID)
        let modes = ProfileTradeFixtures.accountModes()
        accounts = PropFirmFixtures.accounts(owner: profileID)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        detailCache.seed(accounts: accounts, for: profileID)
        payoutTotal = ProfilePayoutTotals.sum(
            from: ProfileAchievementFixtures.samples(owner: profileID)
        )
        tradeInputs = samples.map { trade in
            DashboardChartMetrics.Input(
                trade: trade,
                accountType: trade.accountID.flatMap {
                    modes[$0].map(ProfileStatisticsMetrics.accountTypeString(for:))
                }
            )
        }
        detailCache.seed(trades: samples)
        recompute()
    }

    private static func compactSize(_ amount: Decimal) -> String {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        if value >= 1_000 {
            let k = value / 1_000
            if k.rounded() == k { return "\(Int(k))K" }
            return String(format: "%.1fK", k)
        }
        return DashboardViewModel.money(amount)
    }

    private func apply(trades list: [Trade], accounts: [TradingAccount], profileID: ProfileID) {
        self.accounts = accounts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let accountTypes = Dictionary(
            uniqueKeysWithValues: accounts.map {
                ($0.id, ProfileStatisticsMetrics.accountTypeString(for: $0.mode))
            }
        )
        tradeInputs = list.map { trade in
            DashboardChartMetrics.Input(
                trade: trade,
                accountType: trade.accountID.flatMap { accountTypes[$0] }
            )
        }
    }

    private func recompute() {
        let result = DashboardChartMetrics.compute(
            from: tradeInputs,
            accountFilter: accountFilter,
            dateRange: dateRange,
            payoutTotal: payoutTotal
        )
        summary = result
        recentTrades = tradeInputs
            .map(\.trade)
            .filter { trade in
                switch accountFilter {
                case .all: return true
                case .account(let id): return trade.accountID == id
                }
            }
            .filter { dateRange.contains($0.exitAt ?? $0.entryAt) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .map { $0 }
    }

    // MARK: - Realtime (idle subscribe — no polling)

    private func startRealtime(profileID: ProfileID) async {
        guard let realtimeHub else { return }
        await stopRealtime()
        let channel = RealtimeChannelID(kind: .profile, topic: "dashboard:\(profileID.rawValue)")
        watchedChannel = channel
        try? await realtimeHub.subscriptions.subscribe(channel)
        // Product trade postgres_changes are not joined yet — subscription marks the
        // dashboard channel as active so incremental hydrate can attach later without polling.
        realtimeTask = Task { [weak self] in
            // Idle hold — cancelled on disappear / stopRealtime.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
            _ = self
        }
    }

    private func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        guard let realtimeHub, let channel = watchedChannel else { return }
        try? await realtimeHub.subscriptions.unsubscribe(channel)
        watchedChannel = nil
    }

    // MARK: - Format

    static func money(_ value: Decimal) -> String {
        ProfileDisplay.formatMoney(value)
    }

    static func factor(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }
}
