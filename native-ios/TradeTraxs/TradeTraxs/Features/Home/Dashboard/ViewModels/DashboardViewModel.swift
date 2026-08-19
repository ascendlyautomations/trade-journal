import Foundation
import Observation

/// Home Dashboard — session-cached trades → presentation metrics → idle.
///
/// Load path: Initial Load → Session Cache → Repository → Realtime subscribe → Idle.
/// Filter changes recompute locally; pull-to-refresh is the only forced refetch.
///
/// Bootstrap is progressive:
/// 1. Trades + accounts (blocking for first useful render)
/// 2. Achievements / payouts (deferred — updates Payouts chip when ready)
///
/// `home.dashboard` is intentionally not called — it duplicated a 500-trade fetch
/// and never drove UI math.
@Observable
@MainActor
final class DashboardViewModel {
    private(set) var phase: DashboardLoadPhase = .idle
    private(set) var summary: DashboardChartMetrics.Summary?
    private(set) var accounts: [TradingAccount] = []
    private(set) var accountNames: [TradingAccountID: String] = [:]
    private(set) var isRefreshing = false

    var accountFilter: DashboardAccountFilter = .all
    var dateRange: DashboardDateRange = .thirtyDays

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
    private var secondaryTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var hasLoaded = false
    private var watchedChannel: RealtimeChannelID?

    /// Test / composition seam — `home` retained for call-site compatibility but unused.
    init(
        home: any HomeRepository,
        trades: any TradeRepository,
        achievements: any AchievementRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        realtimeHub: RealtimeHub? = nil
    ) {
        _ = home
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
            if let account = accounts.first(where: { $0.id == id }) {
                return TradingAccountDisplay.title(for: account, audience: .owner)
            }
            return accountNames[id] ?? "Account"
        }
    }

    /// Compact hero KPI row — glanceable outcomes (Net P&L lives on the equity hero).
    var metricChips: [DashboardMetricChip] {
        guard let summary else { return [] }
        return [
            DashboardMetricChip(
                id: "win",
                label: "Win Rate",
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
                id: "rr",
                label: "Avg RR",
                value: summary.averageRR.map { String(format: "%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "—",
                tone: .neutral
            ),
            DashboardMetricChip(
                id: "trades",
                label: "Trades",
                value: "\(summary.tradeCount)",
                tone: .neutral
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
        ]
    }

    /// Present only when a single prop-firm account is selected.
    var propFirmStatus: PropFirmStatusSnapshot? {
        guard let account = selectedAccount, account.isPropFirmAccount else { return nil }
        let trades = tradeInputs.map(\.trade)
        return PropFirmStatusSnapshot.build(account: account, trades: trades)
    }

    /// Single-account selection from the account filter (nil for All Accounts).
    var selectedAccount: TradingAccount? {
        guard case .account(let id) = accountFilter else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    /// Starting balance for a single prop account — presentation offset only.
    var equityHeroPropStartingBalance: Decimal? {
        DashboardEquityHeroPresentation.propStartingBalance(forSelectedAccount: selectedAccount)
    }

    var equityHeroTitle: String {
        DashboardEquityHeroPresentation.title(propStartingBalance: equityHeroPropStartingBalance)
    }

    var equityHeroDisplayValue: Decimal {
        guard let summary else { return 0 }
        return DashboardEquityHeroPresentation.displayEquity(
            currentEquity: summary.currentEquity,
            propStartingBalance: equityHeroPropStartingBalance
        )
    }

    var equityHeroChartPoints: [ProfileStatisticsMetrics.EquityPoint] {
        guard let summary else { return [] }
        return DashboardEquityHeroPresentation.chartPoints(
            summary.equityData,
            propStartingBalance: equityHeroPropStartingBalance
        )
    }

    func accountMenuTitle(for account: TradingAccount) -> String {
        TradingAccountDisplay.title(for: account, audience: .owner)
    }

    func openPropFirmDetails() {
        guard case .account(let id) = accountFilter else { return }
        navigationCoordinator.open(.home(.propFirm(id)))
    }

    /// Performance section detail cards — supporting metrics below the KPI row.
    var performanceCards: [DashboardMetricChip] {
        guard let summary else { return [] }
        return [
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
            DashboardMetricChip(
                id: "payouts",
                label: "Payouts",
                value: ProfileDisplay.formatMoney(summary.payouts),
                tone: (summary.payouts ?? 0) > 0 ? .positive : .neutral
            ),
        ]
    }

    func loadIfNeeded() {
        if hasLoaded {
            SessionNetworkProbe.record(.cacheHit, resource: "dashboard.navigationReturn")
            if let profileID {
                Task { await startRealtime(profileID: profileID) }
            }
            return
        }
        guard loadTask == nil else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        secondaryTask?.cancel()
        isRefreshing = true
        await performLoad(forceNetwork: true)
        isRefreshing = false
    }

    /// Mutation observer — patch when possible; never full refetch for a single insert/update/delete.
    func handleJournalMutation() {
        switch TradeJournalMutationStore.shared.latest {
        case .created(let trade), .updated(let trade):
            upsertTrade(trade)
        case .deleted(let id, _):
            removeTrade(id: id)
        case .bulkImport, .none:
            Task { await refresh() }
        }
    }

    func handleAccountMutation() {
        Task { await reloadAccountsOnly() }
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
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.home(.calendar))
    }

    func openManageAccounts() {
        ExperienceHaptics.play(.selection)
        // Preserve Dashboard filter — only switches to Settings stack on Profile tab.
        navigationCoordinator.openSettings([.tradingAccounts])
    }

    func openTradesList() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.home(.trades))
    }

    func openReports() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.home(.reports))
    }

    // MARK: - Chart browse (presentation handoff → Trade History)

    func browseWins() {
        seedAndOpenTrades { filters in
            filters.result = .wins
        }
    }

    func browseLosses() {
        seedAndOpenTrades { filters in
            filters.result = .losses
        }
    }

    func browseSession(_ label: String) {
        seedAndOpenTrades(sessionLabel: label) { _ in }
    }

    func browseWeekday(label: String) {
        guard let weekday = TradeHistoryLaunchSeed.calendarWeekday(forHeatmapLabel: label) else {
            openTradesList()
            return
        }
        seedAndOpenTrades(weekday: weekday) { _ in }
    }

    func browseHour(label: String) {
        guard let hour = Int(label) else {
            openTradesList()
            return
        }
        seedAndOpenTrades(hour: hour) { _ in }
    }

    func browseLong() {
        seedAndOpenTrades { filters in
            filters.direction = .long
        }
    }

    func browseShort() {
        seedAndOpenTrades { filters in
            filters.direction = .short
        }
    }

    func browseHoldBucket(label: String) {
        let range = TradeHistoryLaunchSeed.holdRange(forBucketLabel: label)
        seedAndOpenTrades(holdRange: range) { _ in }
    }

    private func seedAndOpenTrades(
        weekday: Int? = nil,
        hour: Int? = nil,
        sessionLabel: String? = nil,
        holdRange: TradeHistoryLaunchSeed.HoldSecondsRange? = nil,
        mutate: (inout TradeHistoryFilters) -> Void
    ) {
        ExperienceHaptics.play(.selection)
        var filters = tradeHistoryFiltersPreservingDashboardContext()
        mutate(&filters)
        TradeHistoryLaunchSeed.set(
            .init(
                filters: filters,
                searchText: "",
                weekday: weekday,
                hour: hour,
                sessionLabel: sessionLabel,
                holdSecondsRange: holdRange
            )
        )
        navigationCoordinator.open(.home(.trades))
    }

    /// Maps Dashboard account + date range into existing Trade History filters.
    private func tradeHistoryFiltersPreservingDashboardContext() -> TradeHistoryFilters {
        var filters = TradeHistoryFilters()
        filters.account = accountFilter
        let calendar = Calendar.current
        let now = Date()
        switch dateRange {
        case .all:
            filters.dateRange = .allTime
        case .sevenDays:
            filters.dateRange = .custom
            filters.customStart = calendar.date(byAdding: .day, value: -7, to: now)
            filters.customEnd = now
        case .thirtyDays:
            filters.dateRange = .last30Days
        case .ninetyDays:
            filters.dateRange = .custom
            filters.customStart = calendar.date(byAdding: .day, value: -90, to: now)
            filters.customEnd = now
        case .ytd:
            filters.dateRange = .custom
            var comps = DateComponents()
            comps.year = calendar.component(.year, from: now)
            comps.month = 1
            comps.day = 1
            filters.customStart = calendar.date(from: comps)
            filters.customEnd = now
        }
        return filters
    }

    func onDisappear() {
        Task { await stopRealtime() }
    }

    // MARK: - Load

    private func performLoad(forceNetwork: Bool = false) async {
        DashboardLoadProbe.beginSession()

        let userID = await session.currentUserID
        let profileID = ProfileID(userID?.rawValue ?? "dev.screenshot")
        self.profileID = profileID

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            await DashboardLoadProbe.measure(
                "dashboard.fixtures",
                kind: .local,
                blocksFirstUsefulRender: true
            ) {
                applyFixtures(profileID: profileID)
            }
            hasLoaded = true
            phase = .loaded
            DashboardLoadProbe.markFirstUsefulRender()
            DashboardLoadProbe.markFullHydration()
            await startRealtime(profileID: profileID)
            loadTask = nil
            return
        }

        if summary == nil { phase = .loading }

        do {
            // Session cache — recompute only; never refetch analytics on filter changes
            // or navigation return while this ViewModel is alive.
            if !forceNetwork, hasLoaded, !tradeInputs.isEmpty {
                SessionNetworkProbe.record(.cacheHit, resource: "dashboard.session")
                await DashboardLoadProbe.measure(
                    "dashboard.sessionCache.recompute",
                    kind: .cache,
                    blocksFirstUsefulRender: true
                ) {
                    recompute()
                }
                phase = .loaded
                DashboardLoadProbe.markFirstUsefulRender()
                DashboardLoadProbe.markFullHydration()
                loadTask = nil
                return
            }

            // Accounts + trades in parallel — both needed for first useful render,
            // but serializing them doubles wall-clock latency on cold load.
            async let accountsTask = bootstrapAccounts(
                profileID: profileID,
                forceNetwork: forceNetwork
            )
            async let tradesTask = bootstrapTrades(profileID: profileID, forceNetwork: forceNetwork)
            let fetchedAccounts = try await accountsTask
            let page = try await tradesTask
            detailCache.seed(trades: page.items)

            // Seed payouts from cache immediately when available so first paint is complete.
            if payoutTotal == nil, let stats = detailCache.stats(for: profileID) {
                payoutTotal = stats.payoutTotal
            }

            apply(trades: page.items, accounts: fetchedAccounts, profileID: profileID)
            guard !Task.isCancelled else { return }
            hasLoaded = true
            recompute()
            phase = .loaded
            DashboardLoadProbe.markFirstUsefulRender()

            await startRealtime(profileID: profileID)

            // Deferred: achievements only feed the Payouts chip — never block first useful render.
            secondaryTask?.cancel()
            secondaryTask = Task { [weak self] in
                await self?.hydratePayouts(profileID: profileID, forceNetwork: forceNetwork)
                DashboardLoadProbe.markFullHydration()
            }
        } catch {
            guard !Task.isCancelled else { return }
            if summary == nil {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func bootstrapAccounts(
        profileID: ProfileID,
        forceNetwork: Bool
    ) async throws -> [TradingAccount] {
        if !forceNetwork,
           let cachedAccounts = SessionAccountsStore.shared.cached(for: profileID)
            ?? detailCache.accounts(for: profileID),
           !cachedAccounts.isEmpty
        {
            SessionAccountsStore.shared.seed(
                cachedAccounts,
                for: profileID,
                detailCache: detailCache
            )
            SessionNetworkProbe.record(.cacheHit, resource: "dashboard.accounts")
            return await DashboardLoadProbe.measure(
                "dashboard.accounts.cacheHit",
                kind: .cache,
                blocksFirstUsefulRender: true,
                rowCount: cachedAccounts.count
            ) { cachedAccounts }
        }
        let fetched = try await SessionAccountsStore.shared.accounts(
            for: profileID,
            detailCache: detailCache,
            repository: trades,
            forceNetwork: forceNetwork
        )
        return await DashboardLoadProbe.measure(
            "dashboard.accounts",
            kind: .network,
            blocksFirstUsefulRender: true,
            rowCount: fetched.count,
            note: "accounts for profile"
        ) { fetched }
    }

    private func bootstrapTrades(
        profileID: ProfileID,
        forceNetwork: Bool
    ) async throws -> CursorPage<Trade> {
        // Disk → session owner-trades cache → one bounded SELECT.
        if !forceNetwork,
           let disk = SessionDiskCache.loadOwnerTrades(for: profileID),
           SessionOwnerTradesStore.shared.cached(for: profileID) == nil
        {
            SessionOwnerTradesStore.shared.seed(disk, for: profileID, detailCache: detailCache)
        }
        let items = try await DashboardLoadProbe.measure(
            "dashboard.trades",
            kind: (!forceNetwork && SessionOwnerTradesStore.shared.isFresh(for: profileID))
                ? .cache : .network,
            blocksFirstUsefulRender: true,
            note: "session owner trades ≤500"
        ) {
            try await SessionOwnerTradesStore.shared.trades(
                for: profileID,
                detailCache: detailCache,
                repository: trades,
                limit: 500,
                forceNetwork: forceNetwork
            )
        }
        return CursorPage(items: items, nextCursor: nil)
    }

    private func hydratePayouts(profileID: ProfileID, forceNetwork: Bool) async {
        if !forceNetwork, payoutTotal != nil { return }
        do {
            let achievementPage = try await DashboardLoadProbe.measure(
                "dashboard.achievements",
                kind: .network,
                blocksFirstUsefulRender: false,
                note: "public achievements for payouts chip"
            ) {
                try await achievements.achievements(
                    for: profileID,
                    page: PageRequest(limit: 500),
                    publicOnly: true
                )
            }
            guard !Task.isCancelled else { return }
            detailCache.seed(achievements: achievementPage.items)
            payoutTotal = ProfilePayoutTotals.sum(from: achievementPage.items)
            recompute()
        } catch {
            if payoutTotal == nil, let stats = detailCache.stats(for: profileID) {
                payoutTotal = stats.payoutTotal
                recompute()
            }
        }
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

    private func upsertTrade(_ trade: Trade) {
        guard hasLoaded else { return }
        SessionNetworkProbe.record(.localMutation, resource: "dashboard.trades", detail: trade.id.rawValue)
        SessionOwnerTradesStore.shared.upsert(trade, detailCache: detailCache)
        let accountType = trade.accountID.flatMap { id in
            accounts.first(where: { $0.id == id }).map {
                ProfileStatisticsMetrics.accountTypeString(for: $0.mode)
            }
        }
        tradeInputs.removeAll { $0.trade.id == trade.id }
        tradeInputs.insert(
            DashboardChartMetrics.Input(trade: trade, accountType: accountType),
            at: 0
        )
        recompute()
    }

    private func removeTrade(id: TradeID) {
        guard hasLoaded else { return }
        SessionNetworkProbe.record(.localMutation, resource: "dashboard.trades.remove", detail: id.rawValue)
        detailCache.removeTrade(id: id)
        tradeInputs.removeAll { $0.trade.id == id }
        recompute()
    }

    private func reloadAccountsOnly() async {
        guard let profileID else { return }
        do {
            SessionAccountsStore.shared.invalidate(profileID: profileID)
            let loaded = try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: detailCache,
                repository: trades,
                forceNetwork: true
            )
            accounts = loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
            // Rebind account types on existing trades without refetching trades.
            let accountTypes = Dictionary(
                uniqueKeysWithValues: accounts.map {
                    ($0.id, ProfileStatisticsMetrics.accountTypeString(for: $0.mode))
                }
            )
            tradeInputs = tradeInputs.map { input in
                DashboardChartMetrics.Input(
                    trade: input.trade,
                    accountType: input.trade.accountID.flatMap { accountTypes[$0] } ?? input.accountType
                )
            }
            recompute()
        } catch {
            // keep existing accounts
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
    }

    // MARK: - Realtime (idle subscribe — no polling)

    private func startRealtime(profileID: ProfileID) async {
        guard let realtimeHub else { return }
        let channel = RealtimeChannelID(kind: .profile, topic: "dashboard:\(profileID.rawValue)")
        // Deduplicate — navigation return must not open a second retain on the same channel.
        if watchedChannel == channel, realtimeTask != nil { return }
        await stopRealtime()
        watchedChannel = channel
        try? await realtimeHub.subscriptions.subscribe(channel)
        _ = await DashboardLoadProbe.measure(
            "dashboard.realtime.subscribe",
            kind: .realtime,
            blocksFirstUsefulRender: false,
            note: "registry-only until trade postgres_changes attach"
        ) { () }
        // Product trade postgres_changes are not joined yet — subscription marks the
        // dashboard channel as active so incremental hydrate can attach later without polling.
        realtimeTask = Task { [weak self] in
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
