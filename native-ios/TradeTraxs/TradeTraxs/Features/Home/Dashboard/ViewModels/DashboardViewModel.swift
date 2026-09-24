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
    private(set) var psychologyReport: PsychologyAnalyticsReport?
    private(set) var psychologyGuardrailNotices: [PsychologyGuardrailNotice] = []
    private(set) var accounts: [TradingAccount] = []
    private(set) var accountNames: [TradingAccountID: String] = [:]
    private(set) var isRefreshing = false

    var accountFilter: DashboardAccountFilter = .all
    var dateRange: DashboardDateRange = .thirtyDays
    /// Widened preset for the equity hero when the dashboard selection has no trades in-range.
    private(set) var effectiveEquityChartRange: DashboardDateRange = .thirtyDays

    private let trades: any TradeRepository
    private let achievements: any AchievementRepository
    private let dailyCheckIns: any TraderDailyCheckInRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let realtimeHub: RealtimeHub?
    private let rpc: (any RPCClient)?

    private var profileID: ProfileID?
    private var tradeInputs: [DashboardChartMetrics.Input] = []
    private var payoutTotal: Decimal?
    private var loadTask: Task<Void, Never>?
    private var secondaryTask: Task<Void, Never>?
    private var hasLoaded = false
    private var coldLoadFinished = false
    private var contractDecodeFailed = false
    private var loadGeneration: UInt64 = 0
    private var pendingHistoryBackfill = false
    private var watchedChannel: RealtimeChannelID?
    /// Manual date-range override (persists across account switches).
    private var hasUserSelectedDateRangeForCurrentFilter = false
    /// When true, pick the best preset for ``accountFilter`` once trade history is authoritative.
    private var pendingAutomaticDateRangeResolution = true
    /// True once owner trade history is authoritative enough to pick a date preset.
    private var initialTradeHistoryReady = false
    /// Server-reported total trades (V2 bootstrap); nil on legacy REST bootstrap.
    private var authoritativeTotalTradeCount: Int?
    /// Funded prop-firm payout cycles keyed by account — drives Prop Firm Status card boundaries.
    private var payoutCyclesByAccount: [TradingAccountID: [AccountPayoutCycle]] = [:]
    /// Dashboard V3 authoritative analytical payload (no fat trade window).
    private var analyticsV3Bootstrap: AnalyticsDashboardBootstrapV3?
    private var equityChartSummary: DashboardChartMetrics.Summary?
    private var equityChartAccountFilter: DashboardAccountFilter?
    private var analyticsV3Revision: Int64 = 0
    private var lastAccountScopedSummary: DashboardChartMetrics.Summary?
    private var lastAccountScopedFilter: DashboardAccountFilter?
    private var lastV3MetricsLookup: DashboardAnalyticsAccountMetricsLookup?
    private var accountChartSelectionToken: UInt64 = 0
    private var accountChartHydrateTask: Task<Void, Never>?
    private var aggregateChartSelectionToken: UInt64 = 0
    private var aggregateChartHydrateTask: Task<Void, Never>?
    private var dashboardGRDBBackgroundReconcileScheduled = false
    private var analyticsReconciliationObserver: NSObjectProtocol?

    private var usesDashboardAnalyticsV3: Bool {
        BackendV2FeatureFlags.isEnabled(.dashboardAnalyticsV3)
    }

    private var usesDashboardAnalyticsGRDB: Bool {
        usesDashboardAnalyticsV3 && BackendV2FeatureFlags.isEnabled(.dashboardAnalyticsGRDB)
    }

    /// Test / composition seam — `home` retained for call-site compatibility but unused.
    init(
        home: any HomeRepository,
        trades: any TradeRepository,
        achievements: any AchievementRepository,
        dailyCheckIns: any TraderDailyCheckInRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        realtimeHub: RealtimeHub? = nil,
        rpc: (any RPCClient)? = nil
    ) {
        _ = home
        self.trades = trades
        self.achievements = achievements
        self.dailyCheckIns = dailyCheckIns
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.realtimeHub = realtimeHub
        self.rpc = rpc
    }

    func openPsychologyAnalytics(highlightSection: String? = nil) {
        PsychologyAnalyticsSessionStore.shared.focusSection(highlightSection)
        navigationCoordinator.pushHome(.psychologyAnalytics)
    }

    func psychologySectionID(for category: PsychologyInsightCategory) -> String {
        switch category {
        case .sleep: return "sleep"
        case .mentalState: return "mentalState"
        case .conviction: return "conviction"
        case .discipline: return "discipline"
        case .emotion: return "emotion"
        case .afterLosses: return "afterLosses"
        case .tradeFrequency: return "tradeFrequency"
        case .combined: return "combined"
        }
    }

    var accountFilterTitle: String {
        switch accountFilter {
        case .all:
            return "All Accounts"
        case .account(let id):
            if let account = accounts.first(where: { $0.id == id }) {
                return TradingAccountDisplay.ownerDropdownLine(for: account)
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
                value: summary.averageRR.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "—",
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
        let cycles = payoutCyclesByAccount[account.id] ?? []
        return PropFirmStatusSnapshot.build(
            account: account,
            trades: trades,
            payoutCycles: cycles
        )
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

    var equityHeroSummary: DashboardChartMetrics.Summary? {
        guard equityChartAccountFilter == accountFilter else { return nil }
        return equityChartSummary
    }

    var equityHeroDisplayValue: Decimal {
        guard let heroSummary = equityHeroSummary ?? summary else { return 0 }
        if usesDashboardAnalyticsV3, !selectedChartOverlayLoaded {
            return heroSummary.netPnL
        }
        return DashboardEquityHeroPresentation.displayEquity(
            currentEquity: heroSummary.currentEquity,
            propStartingBalance: equityHeroPropStartingBalance
        )
    }

    var equityHeroChartPoints: [ProfileStatisticsMetrics.EquityPoint] {
        guard equityChartAccountFilter == accountFilter else { return [] }
        if usesDashboardAnalyticsV3, !selectedChartOverlayLoaded {
            return []
        }
        let chartSummary = equityChartSummary ?? summary
        guard let chartSummary else { return [] }
        return DashboardEquityHeroPresentation.chartPoints(
            chartSummary.equityData,
            propStartingBalance: equityHeroPropStartingBalance
        )
    }

    private var selectedChartOverlayLoaded: Bool {
        guard usesDashboardAnalyticsV3 else { return true }
        switch accountFilter {
        case .all:
            return DashboardAnalyticsAggregateChartsStore.shared
                .availability(revision: analyticsV3Revision)
                .isLoaded
        case .account(let id):
            return DashboardAnalyticsAccountChartsStore.shared
                .availability(accountID: id, revision: analyticsV3Revision)
                .isLoaded
        }
    }

    private var selectedAccountChartsLoaded: Bool {
        selectedChartOverlayLoaded
    }

    private var selectedAccountChartsAvailability: DashboardAnalyticsChartsAvailability {
        guard usesDashboardAnalyticsV3 else { return .loaded }
        switch accountFilter {
        case .all:
            return DashboardAnalyticsAggregateChartsStore.shared.availability(revision: analyticsV3Revision)
        case .account(let id):
            return DashboardAnalyticsAccountChartsStore.shared.availability(
                accountID: id,
                revision: analyticsV3Revision
            )
        }
    }

    func accountMenuTitle(for account: TradingAccount) -> String {
        TradingAccountDisplay.ownerDropdownLine(for: account)
    }

    var accountsForMenu: [TradingAccount] {
        let selectedID: TradingAccountID? = {
            if case .account(let id) = accountFilter { return id }
            return nil
        }()
        return OwnerAccountDropdownSupport.menuAccounts(
            profileID: profileID,
            fallback: accounts,
            preservingSelection: selectedID
        )
    }

    var ownerAccountsProfileID: ProfileID? { profileID }

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
        if coldLoadFinished {
            return
        }
        guard loadTask == nil else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask = Task { await performLoad(generation: generation) }
    }

    func refresh() async {
        loadTask?.cancel()
        secondaryTask?.cancel()
        isRefreshing = true
        coldLoadFinished = false
        contractDecodeFailed = false
        dashboardGRDBBackgroundReconcileScheduled = false
        loadGeneration &+= 1
        let generation = loadGeneration
        await performLoad(
            forceNetwork: true,
            generation: generation,
            refreshTrigger: .pullRefresh
        )
        isRefreshing = false
    }

    private func ensureAnalyticsReconciliationObserver() {
        guard analyticsReconciliationObserver == nil, profileID != nil else { return }
        analyticsReconciliationObserver = NotificationCenter.default.addObserver(
            forName: AnalyticsReconciliationUIApply.dashboardCommittedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { await self?.applyDashboardAnalyticsReconciliationNotification(notification) }
        }
    }

    private func applyDashboardAnalyticsReconciliationNotification(_ notification: Notification) async {
        guard usesDashboardAnalyticsV3, AnalyticsReconciliationGate.isEnabled else { return }
        guard let viewerRaw = notification.userInfo?["viewerID"] as? String,
              viewerRaw == profileID?.rawValue
        else { return }
        guard let revision = notification.userInfo?["serverRevision"] as? Int64 else { return }
        guard let cached = DashboardAnalyticsDiskCache.load(viewerID: ProfileID(viewerRaw)),
              cached.revision == revision
        else { return }
        do {
            let applied = try DashboardAnalyticsV3Applier.apply(
                cached.payload,
                expectedViewerID: viewerRaw,
                detailCache: detailCache
            )
            analyticsV3Bootstrap = applied.bootstrap
            analyticsV3Revision = applied.revision
            recompute()
        } catch {
            DashboardAnalyticsGRDBProbe.logFallback(reason: "reconciliation_apply_error")
        }
    }

    /// Mutation observer — patch when possible; never full refetch for a single insert/update/delete.
    func handleJournalMutation() {
        switch TradeJournalMutationStore.shared.latest {
        case .created(let trade), .updated(let trade):
            if usesDashboardAnalyticsV3 {
                if AnalyticsReconciliationGate.isEnabled {
                    break
                }
                scheduleAnalyticsV3RefreshAfterMutation()
            } else {
                upsertTrade(trade)
            }
        case .deleted(let id, _):
            if usesDashboardAnalyticsV3 {
                if AnalyticsReconciliationGate.isEnabled {
                    break
                }
                scheduleAnalyticsV3RefreshAfterMutation()
            } else {
                removeTrade(id: id)
            }
        case .bulkImport:
            if usesDashboardAnalyticsV3, AnalyticsReconciliationGate.isEnabled {
                break
            }
            Task {
                loadTask?.cancel()
                secondaryTask?.cancel()
                loadGeneration &+= 1
                let generation = loadGeneration
                await performLoad(
                    forceNetwork: true,
                    generation: generation,
                    refreshTrigger: .journalMutation
                )
            }
        case .none:
            break
        }
    }

    func handleAccountMutation() {
        switch AccountMutationStore.shared.latestKind {
        case .payoutRecorded(let accountID):
            Task { await reloadAfterPayout(accountID: accountID) }
        case .generic:
            patchAccountsFromSessionStore()
            if usesDashboardAnalyticsV3, !AnalyticsReconciliationGate.isEnabled {
                scheduleAnalyticsV3RefreshAfterMutation()
            }
        }
    }

    func handleContentMutation() {
        guard case .achievement(let achievement) = ContentMutationStore.shared.latest else { return }
        guard achievement.isPublic, ProfilePayoutTotals.isPayout(achievement.kind) else { return }
        detailCache.seed(achievement)
        let prior = payoutTotal ?? 0
        payoutTotal = prior + (achievement.value?.amount ?? 0)
        recompute()
    }

    func handleCheckInMutation() {
        recomputePsychology()
    }

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        guard accountFilter != filter else { return }
        ExperienceHaptics.play(.selection)
        accountFilter = filter
        equityChartSummary = nil
        equityChartAccountFilter = nil
        if case .account(let id) = filter,
           payoutCyclesByAccount[id] == nil,
           let profileID,
           let account = accounts.first(where: { $0.id == id }),
           PropFirmPayoutPolicy.supportsRecordPayout(for: account)
        {
            Task {
                await hydratePropFirmPayoutCycles(
                    profileID: profileID,
                    accountIDs: [id],
                    forceNetwork: false
                )
            }
        }
        recompute()
        if usesDashboardAnalyticsV3 {
            if usesDashboardAnalyticsGRDB, analyticsV3Bootstrap != nil {
                DashboardAnalyticsGRDBProbe.logNetworkAvoided(reason: "account_metrics_local")
            }
            scheduleChartHydration()
        }
    }

    func setDateRange(_ range: DashboardDateRange) {
        guard dateRange != range else { return }
        ExperienceHaptics.play(.selection)
        hasUserSelectedDateRangeForCurrentFilter = true
        pendingAutomaticDateRangeResolution = false
        dateRange = range
        recompute()
        if usesDashboardAnalyticsGRDB, analyticsV3Bootstrap != nil {
            DashboardAnalyticsGRDBProbe.logNetworkAvoided(reason: "preset_local")
        }
    }

    func openCalendar() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.home(.calendar))
    }

    func openManageAccounts() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushHome(.settings(.tradingAccounts))
    }

    func openTradesList() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.home(.trades))
    }

    func openReports() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.home(.reports))
    }

    func openWithdrawalsHistory() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.home(.payouts))
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

    private func performLoad(
        forceNetwork: Bool = false,
        generation: UInt64? = nil,
        isAuthoritativeFollowUp: Bool = false,
        refreshTrigger: DashboardAuthoritativeRefreshTrigger? = nil
    ) async {
        let activeGeneration = generation ?? loadGeneration
        if !forceNetwork, !isAuthoritativeFollowUp {
            DashboardLoadProbe.beginSession()
            DashboardLoadProbe.recordColdAttempt()
        } else {
            DashboardLoadProbe.beginSession(label: "dashboard.refresh")
        }
        defer {
            loadTask = nil
            if !forceNetwork, !isAuthoritativeFollowUp {
                coldLoadFinished = true
            }
        }

        let userID = await session.currentUserID
        let profileID = ProfileID(userID?.rawValue ?? "dev.screenshot")
        self.profileID = profileID
        ensureAnalyticsReconciliationObserver()

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            await SessionNetworkGate.shared.awaitReady()
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
            AuthenticatedLaunchPhasing.markCriticalVisibleSurfaceReady(tab: .home)
            await startRealtime(profileID: profileID)
            loadTask = nil
            return
        }

        if !forceNetwork, !isAuthoritativeFollowUp, summary == nil {
            if await tryPaintFromDiskCache(profileID: profileID, generation: activeGeneration) {
                loadTask = nil
                return
            }
        }

        await SessionNetworkGate.shared.awaitReady()

        if summary == nil { phase = .loading }

        do {
            if usesDashboardAnalyticsV3, BackendV2FeatureFlags.isEnabled(.dashboard), let rpc {
                if try await loadDashboardAnalyticsV3(
                    profileID: profileID,
                    rpc: rpc,
                    forceNetwork: forceNetwork,
                    generation: activeGeneration
                ) {
                    loadTask = nil
                    return
                }
            }

            if BackendV2FeatureFlags.isEnabled(.dashboard), let rpc {
                if let loadResult = try await BootstrapTransportTimeout.run({ [self] in
                    try await loadDashboardV2(
                        profileID: profileID,
                        rpc: rpc,
                        forceNetwork: forceNetwork,
                        trigger: dashboardLoadTrigger(
                            forceNetwork: forceNetwork,
                            isAuthoritativeFollowUp: isAuthoritativeFollowUp,
                            explicit: refreshTrigger
                        ),
                        generation: activeGeneration
                    )
                }) {
                    guard activeGeneration == loadGeneration, !Task.isCancelled else {
                        loadTask = nil
                        return
                    }
                    let v2 = loadResult.applied
                    apply(
                        trades: v2.trades,
                        accounts: v2.accounts,
                        profileID: profileID
                    )
                    noteTradeHistoryApplied(
                        totalTradeCount: v2.totalTradeCount,
                        historyComplete: v2.tradeHistoryComplete
                    )
                    if let payout = v2.payoutTotal {
                        payoutTotal = payout
                    }
                    hasLoaded = true
                    recompute()
                    phase = .loaded
                    #if DEBUG
                    let source: String = switch loadResult.path {
                    case .cache_fresh, .cache_stale_revalidate, .cache_display_only, .error_preserved_cache: "disk"
                    case .v2_rpc: "network"
                    default: "unknown"
                    }
                    ColdLaunchSummaryProbe.markDashboardFirstRender(source: source)
                    #endif
                    DashboardLoadProbe.markFirstUsefulRender()
                    if !AuthenticatedLaunchPhasing.allowsDeferredStartupNetworking {
                        AuthenticatedLaunchPhasing.markCriticalVisibleSurfaceReady(tab: .home)
                    }
                    if v2.payoutTotal != nil {
                        DashboardLoadProbe.markFullHydration()
                    }
                    noteDeferredHistoryBackfillIfNeeded(
                        profileID: profileID,
                        generation: activeGeneration,
                        tradeHistoryComplete: v2.tradeHistoryComplete
                    )
                    secondaryTask?.cancel()
                    secondaryTask = Task { [weak self] in
                        await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
                        await self?.runSecondaryHydration(
                            profileID: profileID,
                            forceNetwork: forceNetwork,
                            skipPayouts: v2.payoutTotal != nil
                        )
                        if v2.payoutTotal == nil {
                            DashboardLoadProbe.markFullHydration()
                        }
                    }
                    await startRealtime(profileID: profileID)
                    loadTask = nil
                    return
                }
            }

            // Legacy REST bootstrap (flag OFF or controlled RPC fallback).
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
                AuthenticatedLaunchPhasing.markCriticalVisibleSurfaceReady(tab: .home)
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
            noteTradeHistoryApplied(
                totalTradeCount: page.items.count,
                historyComplete: forceNetwork || !page.items.isEmpty
            )
            guard !Task.isCancelled else {
                loadTask = nil
                return
            }
            hasLoaded = true
            recompute()
            phase = .loaded
            DashboardLoadProbe.markFirstUsefulRender()
            AuthenticatedLaunchPhasing.markCriticalVisibleSurfaceReady(tab: .home)

            noteDeferredHistoryBackfillIfNeeded(
                profileID: profileID,
                generation: activeGeneration,
                tradeHistoryComplete: forceNetwork || !page.items.isEmpty
            )

            await startRealtime(profileID: profileID)

            // Deferred: achievements only feed the Payouts chip — never block first useful render.
            secondaryTask?.cancel()
            secondaryTask = Task { [weak self] in
                await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
                await self?.runSecondaryHydration(
                    profileID: profileID,
                    forceNetwork: forceNetwork,
                    skipPayouts: false
                )
                DashboardLoadProbe.markFullHydration()
            }
        } catch is CancellationError {
            if summary == nil { phase = .idle }
        } catch {
            guard !Task.isCancelled else { return }
            if isContractDecodeFailure(error) {
                contractDecodeFailed = true
            }
            if summary == nil {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
    }

    private func isContractDecodeFailure(_ error: Error) -> Bool {
        if error is DecodingError { return true }
        if let rpc = error as? BackendV2RPCError, case .decode = rpc { return true }
        return false
    }

    /// Returns nil to fall through to legacy REST bootstrap.
    @discardableResult
    private func tryPaintFromDiskCache(profileID: ProfileID, generation: UInt64) async -> Bool {
        guard BackendV2FeatureFlags.isEnabled(.dashboard), rpc != nil else { return false }
        if usesDashboardAnalyticsV3 {
            return await tryPaintFromAnalyticsV3DiskCache(profileID: profileID, generation: generation)
        }
        guard let cached = BackendV2BootstrapDiskCache.loadDashboard(viewerID: profileID.rawValue) else {
            return false
        }
        do {
            let v2 = try await DashboardBootstrapApplier.apply(
                cached.bootstrap,
                expectedViewerID: profileID.rawValue,
                detailCache: detailCache
            )
            guard generation == loadGeneration, !Task.isCancelled else { return false }
            apply(trades: v2.trades, accounts: v2.accounts, profileID: profileID)
            noteTradeHistoryApplied(
                totalTradeCount: v2.totalTradeCount,
                historyComplete: v2.tradeHistoryComplete
            )
            if let payout = v2.payoutTotal {
                payoutTotal = payout
            }
            hasLoaded = true
            recompute()
            phase = .loaded
            #if DEBUG
            ColdLaunchSummaryProbe.markDashboardFirstRender(source: "disk")
            #endif
            DashboardLoadProbe.markFirstUsefulRender()
            if v2.payoutTotal != nil {
                DashboardLoadProbe.markFullHydration()
            }
            AuthenticatedLaunchPhasing.markCriticalVisibleSurfaceReady(tab: .home)
            noteDeferredHistoryBackfillIfNeeded(
                profileID: profileID,
                generation: generation,
                tradeHistoryComplete: v2.tradeHistoryComplete
            )
            if cached.freshness != .fresh {
                scheduleAuthoritativeDashboardRefresh(generation: generation)
            }
            secondaryTask?.cancel()
            secondaryTask = Task { [weak self] in
                await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
                await self?.runSecondaryHydration(
                    profileID: profileID,
                    forceNetwork: false,
                    skipPayouts: v2.payoutTotal != nil
                )
                if v2.payoutTotal == nil {
                    DashboardLoadProbe.markFullHydration()
                }
            }
            await SessionNetworkGate.shared.awaitReady()
            await startRealtime(profileID: profileID)
            return true
        } catch {
            return false
        }
    }

    private func scheduleAuthoritativeDashboardRefresh(generation: UInt64) {
        Task { [weak self] in
            await SessionNetworkGate.shared.awaitReady()
            await self?.performLoad(
                forceNetwork: true,
                generation: generation,
                isAuthoritativeFollowUp: true
            )
        }
    }

    private func dashboardLoadTrigger(
        forceNetwork: Bool,
        isAuthoritativeFollowUp: Bool,
        explicit: DashboardAuthoritativeRefreshTrigger?
    ) -> DashboardAuthoritativeRefreshTrigger {
        if let explicit { return explicit }
        if isAuthoritativeFollowUp { return .staleAuthoritative }
        if forceNetwork { return .pullRefresh }
        return .cold
    }

    private func noteDeferredHistoryBackfillIfNeeded(
        profileID: ProfileID,
        generation: UInt64,
        tradeHistoryComplete: Bool
    ) {
        guard pendingAutomaticDateRangeResolution else { return }

        if tradeHistoryComplete {
            return
        }

        if let last = DashboardAuthoritativeRefreshCoordinator.shared.lastSuccessfulNetworkRefresh(
            viewerID: profileID
        ), last.tradeHistoryComplete {
            return
        }

        pendingHistoryBackfill = true
        scheduleDeferredOwnerTradesBackfill(profileID: profileID, generation: generation)
    }

    private func scheduleDeferredOwnerTradesBackfill(profileID: ProfileID, generation: UInt64) {
        Task { [weak self] in
            await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
            await DashboardAuthoritativeRefreshCoordinator.shared.awaitInFlightIfNeeded(
                viewerID: profileID
            )
            guard let self, self.pendingHistoryBackfill, generation == self.loadGeneration else { return }
            await self.refreshExtendedOwnerTradesIfNeeded(profileID: profileID, generation: generation)
            self.pendingHistoryBackfill = false
        }
    }

    private func loadDashboardV2(
        profileID: ProfileID,
        rpc: any RPCClient,
        forceNetwork: Bool,
        trigger: DashboardAuthoritativeRefreshTrigger,
        generation: UInt64
    ) async throws -> DashboardBootstrapLoadResult? {
        do {
            return try await DashboardBootstrapLoader.load(
                viewerID: profileID,
                rpc: rpc,
                detailCache: detailCache,
                forceNetwork: forceNetwork,
                trigger: trigger,
                loadGeneration: generation,
                currentGeneration: { [weak self] in self?.loadGeneration ?? 0 }
            )
        } catch DashboardBootstrapLoaderError.flagOff, DashboardBootstrapLoaderError.rpcUnavailable {
            return nil
        }
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
                detailCache: detailCache,
                kind: nil
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
            forceNetwork: forceNetwork,
            requiresFullOwnerSnapshot: true
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
            SessionOwnerTradesStore.shared.seed(
                disk.trades,
                for: profileID,
                detailCache: detailCache,
                historyComplete: disk.historyComplete,
                totalTradeCount: disk.totalTradeCount
            )
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
        let samples: [Trade]
        let modes: [TradingAccountID: TradingAccountMode]
        let seededAccounts: [TradingAccount]
        if profileID == DemoExperienceSupport.profileID {
            samples = DemoCanonicalDataset.trades()
            modes = DemoCanonicalDataset.accountModes()
            seededAccounts = DemoCanonicalDataset.accounts()
        } else {
            samples = ProfileTradeFixtures.samples(owner: profileID)
            modes = ProfileTradeFixtures.accountModes()
            seededAccounts = PropFirmFixtures.accounts(owner: profileID)
        }
        accounts = seededAccounts
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        detailCache.seed(accounts: accounts, for: profileID)
        payoutTotal = ProfilePayoutTotals.sum(
            from: profileID == DemoExperienceSupport.profileID
                ? DemoCanonicalDataset.achievements()
                : ProfileAchievementFixtures.samples(owner: profileID)
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
        noteTradeHistoryApplied(
            totalTradeCount: samples.count,
            historyComplete: true
        )
        recompute()
    }

    private static func compactSize(_ amount: Decimal) -> String {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        if value >= 1_000 {
            let k = value / 1_000
            if k.rounded() == k {
                return "\(NumberDisplay.integer(Int(k)))K"
            }
            return "\(NumberDisplay.decimal(k, minimumFractionDigits: 1, maximumFractionDigits: 1))K"
        }
        return DashboardViewModel.money(amount)
    }

    private func apply(trades list: [Trade], accounts: [TradingAccount], profileID: ProfileID) {
        MainThreadWorkProbe.measure("dashboard.applyHydration", surface: "dashboard") {
            self.accounts = accounts.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
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
    }

    private func upsertTrade(_ trade: Trade) {
        guard hasLoaded else { return }
        SessionNetworkProbe.record(.localMutation, resource: "dashboard.trades", detail: trade.id.rawValue)
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
        tradeInputs.removeAll { $0.trade.id == id }
        recompute()
    }

    private func patchAccountsFromSessionStore() {
        guard let profileID else { return }
        guard let cached = SessionAccountsStore.shared.cached(for: profileID)
            ?? detailCache.accounts(for: profileID)
        else {
            Task { await reloadAccountsOnly() }
            return
        }
        accounts = cached.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        recompute()
    }

    private func reloadAccountsOnly() async {
        guard let profileID else { return }
        SessionAccountsStore.shared.invalidate(profileID: profileID)
        await ensureFullOwnerAccounts(profileID: profileID, forceNetwork: true)
    }

    private func reloadAfterPayout(accountID: TradingAccountID) async {
        guard let profileID else { return }
        SessionAccountsStore.shared.invalidate(profileID: profileID)
        SessionPayoutCyclesStore.shared.invalidate(accountID: accountID, profileID: profileID)
        await ensureFullOwnerAccounts(profileID: profileID, forceNetwork: true)
        await hydratePropFirmPayoutCycles(
            profileID: profileID,
            accountIDs: [accountID],
            forceNetwork: true
        )
        #if DEBUG
        if let snapshot = propFirmStatus {
            PayoutCycleRefreshProbe.logDashboardReload(
                accountID: accountID,
                cycles: payoutCyclesByAccount[accountID] ?? [],
                snapshot: snapshot
            )
        }
        #endif
    }

    private func ensureFullOwnerAccounts(profileID: ProfileID?, forceNetwork: Bool = false) async {
        guard let profileID else { return }
        do {
            let loaded = try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: detailCache,
                repository: trades,
                forceNetwork: forceNetwork,
                requiresFullOwnerSnapshot: true
            )
            accounts = loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
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
        resolveAutomaticDateRangeIfNeeded()
        if usesDashboardAnalyticsV3, let bootstrap = analyticsV3Bootstrap {
            recomputeFromAnalyticsV3(bootstrap: bootstrap)
            return
        }
        let result = DashboardChartMetrics.compute(
            from: tradeInputs,
            accountFilter: accountFilter,
            dateRange: dateRange,
            payoutTotal: payoutTotal
        )
        summary = result
        refreshEquityChartPresentation()
        recomputePsychology()
    }

    private func chartOverlayForFilter() -> [String: AnalyticsDashboardChartsPresetV1]? {
        guard selectedChartOverlayLoaded else { return nil }
        switch accountFilter {
        case .all:
            return DashboardAnalyticsAggregateChartsStore.shared.charts(revision: analyticsV3Revision)
        case .account(let id):
            return DashboardAnalyticsAccountChartsStore.shared.charts(
                accountID: id,
                revision: analyticsV3Revision
            )
        }
    }

    private func scheduleChartHydration() {
        scheduleAccountChartHydration()
        scheduleAggregateChartHydration()
    }

    private func scheduleAccountChartHydration() {
        accountChartSelectionToken = DashboardAnalyticsAccountChartsCoordinator.bumpSelection()
        let token = accountChartSelectionToken
        accountChartHydrateTask?.cancel()
        accountChartHydrateTask = Task(priority: .userInitiated) { [weak self] in
            await self?.hydrateAccountChartsIfNeeded(selectionToken: token)
        }
    }

    private func scheduleAggregateChartHydration() {
        aggregateChartSelectionToken = DashboardAnalyticsAggregateChartsCoordinator.bumpSelection()
        let token = aggregateChartSelectionToken
        aggregateChartHydrateTask?.cancel()
        aggregateChartHydrateTask = Task(priority: .userInitiated) { [weak self] in
            await self?.hydrateAggregateChartsIfNeeded(selectionToken: token)
        }
    }

    private func hydrateAccountChartsIfNeeded(selectionToken: UInt64) async {
        guard usesDashboardAnalyticsV3, let rpc, let profileID, case .account(let id) = accountFilter else {
            return
        }
        guard selectionToken == accountChartSelectionToken else { return }

        if await trySeedAccountChartsFromGRDB(
            accountID: id,
            profileID: profileID,
            selectionToken: selectionToken
        ) {
            recompute()
            return
        }

        let applied = await DashboardAnalyticsAccountChartsCoordinator.loadIfNeeded(
            selectedAccountID: id,
            selectionToken: selectionToken,
            revision: analyticsV3Revision,
            viewerID: profileID,
            rpc: rpc
        )
        guard applied else { return }
        guard selectionToken == accountChartSelectionToken else { return }
        guard case .account(let current) = accountFilter, current == id else { return }
        recompute()
    }

    private func hydrateAggregateChartsIfNeeded(selectionToken: UInt64) async {
        guard usesDashboardAnalyticsV3, let rpc, let profileID, accountFilter == .all else {
            return
        }
        guard selectionToken == aggregateChartSelectionToken else { return }

        if await trySeedAggregateChartsFromGRDB(
            profileID: profileID,
            selectionToken: selectionToken
        ) {
            recompute()
            return
        }

        let applied = await DashboardAnalyticsAggregateChartsCoordinator.loadIfNeeded(
            selectionToken: selectionToken,
            revision: analyticsV3Revision,
            viewerID: profileID,
            rpc: rpc
        )
        guard applied else { return }
        guard selectionToken == aggregateChartSelectionToken else { return }
        guard accountFilter == .all else { return }
        recompute()
    }

    private func recomputeFromAnalyticsV3(bootstrap: AnalyticsDashboardBootstrapV3) {
        let resolution = DashboardAnalyticsMapper.resolve(
            in: bootstrap,
            accountFilter: accountFilter,
            dateRange: dateRange,
            accountCharts: chartOverlayForFilter()
        )
        lastV3MetricsLookup = resolution

        switch resolution {
        case .aggregate(let bundle):
            lastAccountScopedSummary = nil
            lastAccountScopedFilter = nil
            summary = DashboardAnalyticsMapper.summary(from: bundle, payoutTotal: payoutTotal)
        case .account(let bundle, _):
            let next = DashboardAnalyticsMapper.summary(from: bundle, payoutTotal: payoutTotal)
            summary = next
            lastAccountScopedSummary = next
            lastAccountScopedFilter = accountFilter
        case .accountMetricsMissing:
            if accountFilter == lastAccountScopedFilter, let lastAccountScopedSummary {
                summary = lastAccountScopedSummary
            } else {
                summary = nil
            }
        }

        refreshEquityChartPresentation(bootstrap: bootstrap)

        guard let bundle = DashboardAnalyticsMapper.bundle(
            in: bootstrap,
            accountFilter: accountFilter,
            dateRange: dateRange,
            accountCharts: chartOverlayForFilter()
        ) else {
            recomputePsychology()
            return
        }
        let equityCount = selectedChartOverlayLoaded
            ? (DashboardAnalyticsMapper.bundle(
                in: bootstrap,
                accountFilter: accountFilter,
                dateRange: effectiveEquityChartRange,
                accountCharts: chartOverlayForFilter()
            )?.equity.points.count ?? 0)
            : 0
        DashboardAnalyticsV3Probe.log(
            source: "local",
            reason: "recompute",
            range: DashboardAnalyticsMapper.presetKey(for: dateRange),
            account: accountFilterTitle,
            mode: "all_non_backtest",
            revision: analyticsV3Revision,
            payloadBytes: nil,
            summaryCount: bootstrap.data.aggregatePresets.count,
            dailyRows: 0,
            equityPoints: equityCount,
            elapsedMs: nil
        )
        #if DEBUG
        if case .account = accountFilter {
            print(
                "[DashboardV3] chartsAvailability=\(selectedAccountChartsAvailability) " +
                    "equityAuthoritative=\(selectedAccountChartsLoaded)"
            )
        }
        #endif
        #if DEBUG
        runV3ParityAgainstLegacyDiskCacheIfPresent(bootstrap: bootstrap)
        #endif
        recomputePsychology()
    }

    #if DEBUG
    private func runV3ParityAgainstLegacyDiskCacheIfPresent(bootstrap: AnalyticsDashboardBootstrapV3) {
        guard let profileID else { return }
        guard let cached = BackendV2BootstrapDiskCache.loadDashboard(viewerID: profileID.rawValue) else {
            return
        }
        guard let v3Summary = summary else { return }
        let accounts = DashboardBootstrapApplier.mappedAccounts(from: cached.bootstrap, ownerID: profileID)
        var inputs: [DashboardChartMetrics.Input] = []
        for row in cached.bootstrap.data.trade_window {
            let dto = row.asTradeDTO(ownerID: profileID.rawValue)
            if let trade = try? TradeMapper.mapToDomain(dto) {
                let accountType = accounts.first(where: { $0.id == trade.accountID })?.mode.rawValue
                inputs.append(DashboardChartMetrics.Input(trade: trade, accountType: accountType))
            }
        }
        let legacy = DashboardChartMetrics.compute(
            from: inputs,
            accountFilter: accountFilter,
            dateRange: dateRange,
            payoutTotal: payoutTotal
        )
        _ = DashboardAnalyticsV3Parity.compare(
            legacy: legacy,
            v3: v3Summary,
            preset: dateRange,
            account: accountFilter,
            historyComplete: cached.bootstrap.data.trade_window_meta.history_complete,
            v3Lookup: lastV3MetricsLookup,
            chartsAvailability: selectedAccountChartsAvailability
        )
        _ = bootstrap
    }
    #endif

    @discardableResult
    private func loadDashboardAnalyticsV3(
        profileID: ProfileID,
        rpc: any RPCClient,
        forceNetwork: Bool,
        generation: UInt64
    ) async throws -> Bool {
        if !forceNetwork, await tryPaintFromAnalyticsV3DiskCache(profileID: profileID, generation: generation) {
            return true
        }

        if summary == nil {
            DashboardAnalyticsGRDBProbe.logFallback(reason: "cold_miss_visible_network")
        }

        let loadResult = try await DashboardAnalyticsV3Loader.load(
            viewerID: profileID,
            rpc: rpc,
            forceNetwork: forceNetwork
        )
        guard generation == loadGeneration, !Task.isCancelled else { return true }

        let applied = try DashboardAnalyticsV3Applier.apply(
            loadResult.bootstrap,
            expectedViewerID: profileID.rawValue,
            detailCache: detailCache
        )
        analyticsV3Bootstrap = applied.bootstrap
        analyticsV3Revision = applied.revision
        apply(trades: [], accounts: applied.accounts, profileID: profileID)
        if let payout = applied.payoutTotal {
            payoutTotal = payout
        }
        noteTradeHistoryApplied(
            totalTradeCount: applied.bootstrap.data.aggregatePresets["all"]?.metrics.trade_count,
            historyComplete: true
        )
        hasLoaded = true
        recompute()
        phase = .loaded
        DashboardAnalyticsGRDBProbe.logRender(
            source: "network",
            revision: analyticsV3Revision,
            scope: accountFilterTitle,
            preset: DashboardAnalyticsMapper.presetKey(for: dateRange),
            elapsedMs: 0
        )
        scheduleChartHydration()
        #if DEBUG
        ColdLaunchSummaryProbe.markDashboardFirstRender(source: loadResult.source)
        #endif
        DashboardLoadProbe.markFirstUsefulRender()
        AuthenticatedLaunchPhasing.markCriticalVisibleSurfaceReady(tab: .home)
        if applied.payoutTotal != nil {
            DashboardLoadProbe.markFullHydration()
        }
        secondaryTask?.cancel()
        secondaryTask = Task { [weak self] in
            await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
            await self?.runSecondaryHydration(
                profileID: profileID,
                forceNetwork: forceNetwork,
                skipPayouts: applied.payoutTotal != nil
            )
            if applied.payoutTotal == nil {
                DashboardLoadProbe.markFullHydration()
            }
        }
        await startRealtime(profileID: profileID)
        return true
    }

    @discardableResult
    private func tryPaintFromAnalyticsV3DiskCache(profileID: ProfileID, generation: UInt64) async -> Bool {
        if await tryPaintFromGRDBCache(profileID: profileID, generation: generation) {
            return true
        }
        guard let cached = DashboardAnalyticsDiskCache.load(viewerID: profileID) else { return false }
        do {
            let applied = try DashboardAnalyticsV3Applier.apply(
                cached.payload,
                expectedViewerID: profileID.rawValue,
                detailCache: detailCache
            )
            guard generation == loadGeneration, !Task.isCancelled else { return false }
            analyticsV3Bootstrap = applied.bootstrap
            analyticsV3Revision = applied.revision
            apply(trades: [], accounts: applied.accounts, profileID: profileID)
            if let payout = applied.payoutTotal {
                payoutTotal = payout
            }
            noteTradeHistoryApplied(
                totalTradeCount: applied.bootstrap.data.aggregatePresets["all"]?.metrics.trade_count,
                historyComplete: true
            )
            hasLoaded = true
            recompute()
            phase = .loaded
            DashboardAnalyticsGRDBProbe.logRender(
                source: "json",
                revision: analyticsV3Revision,
                scope: accountFilterTitle,
                preset: DashboardAnalyticsMapper.presetKey(for: dateRange),
                elapsedMs: 0
            )
            #if DEBUG
            let breakdown = DashboardAnalyticsV3PayloadProbe.measure(applied.bootstrap)
            DashboardAnalyticsV3PayloadProbe.log(breakdown)
            DashboardAnalyticsV3Probe.log(
                source: "disk",
                reason: "prime",
                range: DashboardAnalyticsMapper.presetKey(for: dateRange),
                account: accountFilterTitle,
                mode: "all_non_backtest",
                revision: analyticsV3Revision,
                payloadBytes: breakdown.totalBytes,
                summaryCount: applied.bootstrap.data.aggregatePresets.count,
                dailyRows: 0,
                equityPoints: nil,
                elapsedMs: nil
            )
            #else
            DashboardAnalyticsV3Probe.log(
                source: "disk",
                reason: "prime",
                range: DashboardAnalyticsMapper.presetKey(for: dateRange),
                account: accountFilterTitle,
                mode: "all_non_backtest",
                revision: analyticsV3Revision,
                payloadBytes: nil,
                summaryCount: applied.bootstrap.data.aggregatePresets.count,
                dailyRows: 0,
                equityPoints: nil,
                elapsedMs: nil
            )
            #endif
            #if DEBUG
            ColdLaunchSummaryProbe.markDashboardFirstRender(source: "disk")
            #endif
            DashboardLoadProbe.markFirstUsefulRender()
            if applied.payoutTotal != nil {
                DashboardLoadProbe.markFullHydration()
            }
            AuthenticatedLaunchPhasing.markCriticalVisibleSurfaceReady(tab: .home)
            #if DEBUG
            AnalyticsShadowReadCoordinator.scheduleColdStartProbeIfNeeded(viewerID: profileID)
            #endif
            secondaryTask?.cancel()
            secondaryTask = Task { [weak self] in
                await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
                await self?.runSecondaryHydration(
                    profileID: profileID,
                    forceNetwork: false,
                    skipPayouts: applied.payoutTotal != nil
                )
            }
            await SessionNetworkGate.shared.awaitReady()
            if usesDashboardAnalyticsGRDB {
                scheduleDashboardGRDBBackgroundReconcile(profileID: profileID, generation: generation)
            } else if cached.revision != applied.revision {
                scheduleAnalyticsV3AuthoritativeRefresh(generation: generation)
            }
            if case .account(let id) = accountFilter {
                if await trySeedAccountChartsFromGRDB(
                    accountID: id,
                    profileID: profileID,
                    selectionToken: accountChartSelectionToken
                ) {
                    recompute()
                }
            } else if accountFilter == .all {
                if await trySeedAggregateChartsFromGRDB(
                    profileID: profileID,
                    selectionToken: aggregateChartSelectionToken
                ) {
                    recompute()
                }
            }
            scheduleChartHydration()
            await startRealtime(profileID: profileID)
            return true
        } catch {
            DashboardAnalyticsGRDBProbe.logFallback(reason: "decode_error")
            return false
        }
    }

    private func scheduleAnalyticsV3AuthoritativeRefresh(generation: UInt64) {
        Task { [weak self] in
            await SessionNetworkGate.shared.awaitReady()
            await self?.performLoad(
                forceNetwork: true,
                generation: generation,
                isAuthoritativeFollowUp: true
            )
        }
    }

    private func scheduleAnalyticsV3RefreshAfterMutation() {
        dashboardGRDBBackgroundReconcileScheduled = false
        DashboardAnalyticsAccountChartsStore.shared.invalidate()
        DashboardAnalyticsAggregateChartsStore.shared.invalidate()
        Task { [weak self] in
            guard let self else { return }
            loadTask?.cancel()
            secondaryTask?.cancel()
            loadGeneration &+= 1
            let generation = loadGeneration
            await performLoad(
                forceNetwork: true,
                generation: generation,
                refreshTrigger: .journalMutation
            )
        }
    }

    /// Clears the one-time automatic preset flag without mutating ``dateRange``.
    /// Equity widening is handled by ``refreshEquityChartPresentation()``.
    private func resolveAutomaticDateRangeIfNeeded() {
        guard pendingAutomaticDateRangeResolution else { return }
        if usesDashboardAnalyticsV3 {
            if analyticsV3Bootstrap != nil {
                pendingAutomaticDateRangeResolution = false
            }
            return
        }
        if !initialTradeHistoryReady {
            if tradeInputs.isEmpty, authoritativeTotalTradeCount == 0 {
                pendingAutomaticDateRangeResolution = false
            }
            return
        }
        pendingAutomaticDateRangeResolution = false
    }

    private func refreshEquityChartPresentation(bootstrap: AnalyticsDashboardBootstrapV3? = nil) {
        let charts = chartOverlayForFilter()
        if let bootstrap {
            effectiveEquityChartRange = DashboardEquityChartRangeResolver.effectiveRange(
                requested: dateRange,
                analyticsBootstrap: bootstrap,
                accountFilter: accountFilter,
                accountCharts: charts
            )
            if let bundle = DashboardAnalyticsMapper.bundle(
                in: bootstrap,
                accountFilter: accountFilter,
                dateRange: effectiveEquityChartRange,
                accountCharts: charts
            ) {
                equityChartSummary = DashboardAnalyticsMapper.summary(from: bundle, payoutTotal: payoutTotal)
            } else {
                equityChartSummary = nil
            }
            if equityChartSummary?.equityData.isEmpty != false,
               let fallbackBundle = DashboardAnalyticsMapper.bundle(
                   in: bootstrap,
                   accountFilter: accountFilter,
                   dateRange: dateRange,
                   accountCharts: charts
               )
            {
                let fallback = DashboardAnalyticsMapper.summary(from: fallbackBundle, payoutTotal: payoutTotal)
                if !fallback.equityData.isEmpty {
                    equityChartSummary = fallback
                }
            }
            equityChartAccountFilter = accountFilter
            return
        }

        effectiveEquityChartRange = DashboardEquityChartRangeResolver.effectiveRange(
            requested: dateRange,
            tradeInputs: tradeInputs,
            accountFilter: accountFilter
        )
        equityChartSummary = DashboardChartMetrics.compute(
            from: tradeInputs,
            accountFilter: accountFilter,
            dateRange: effectiveEquityChartRange,
            payoutTotal: payoutTotal
        )
        equityChartAccountFilter = accountFilter
    }

    private func noteTradeHistoryApplied(totalTradeCount: Int?, historyComplete: Bool) {
        authoritativeTotalTradeCount = totalTradeCount
        initialTradeHistoryReady = historyComplete
    }

    /// Extends owner trade history via the dedicated trades path — never a second full dashboard bootstrap.
    private func refreshExtendedOwnerTradesIfNeeded(profileID: ProfileID, generation: UInt64) async {
        guard generation == loadGeneration, pendingAutomaticDateRangeResolution else { return }
        guard !initialTradeHistoryReady else { return }

        do {
            let page = try await bootstrapTrades(profileID: profileID, forceNetwork: true)
            guard generation == loadGeneration, !Task.isCancelled, pendingAutomaticDateRangeResolution else {
                return
            }
            let fetchedAccounts = try await bootstrapAccounts(profileID: profileID, forceNetwork: false)
            apply(trades: page.items, accounts: fetchedAccounts, profileID: profileID)
            let complete = SessionOwnerTradesStore.shared.isCompleteSnapshot(for: profileID)
            noteTradeHistoryApplied(
                totalTradeCount: authoritativeTotalTradeCount ?? page.items.count,
                historyComplete: complete
            )
            recompute()
        } catch {
            // Preserve current presentation — non-fatal.
        }
    }

    private func recomputePsychology() {
        let trades = DashboardChartMetrics.filteredTrades(
            from: tradeInputs,
            accountFilter: accountFilter,
            dateRange: dateRange
        )
        let report = TraderPsychologyAnalyticsEngine.buildReport(
            trades: trades,
            checkIns: SessionDailyCheckInsStore.shared.checkIns
        )
        psychologyReport = report
        PsychologyAnalyticsSessionStore.shared.update(report)

        let facts = PsychologyCoachFactsBuilder.build(
            report: report,
            trades: trades,
            checkIns: SessionDailyCheckInsStore.shared.checkIns
        )
        let summary = PsychologyCoachDeterministicCoach.buildSummary(from: facts)
        PsychologyCoachSessionStore.shared.update(facts: facts, summary: summary)

        let todayKey = TraderPsychologyAnalyticsFoundation.todayCheckInDateKey()
        let todayCheckIn = SessionDailyCheckInsStore.shared.checkIns.first { $0.checkInDate == todayKey }
            ?? TraderDailyCheckInStore.shared.todayCheckIn
        let todayTrades = enrichedTodayTrades(from: trades, checkIns: SessionDailyCheckInsStore.shared.checkIns)
        let dismissed = Set(PsychologyGuardrailDismissStore.shared.dismissedKeysForToday(tradingDay: todayKey))
        psychologyGuardrailNotices = PsychologyGuardrailEngine.activeNotices(
            facts: facts,
            todayCheckIn: todayCheckIn,
            enrichedTradesToday: todayTrades,
            dismissedKeys: dismissed,
            tradingDay: todayKey
        )
    }

    private func enrichedTodayTrades(
        from trades: [Trade],
        checkIns: [TraderDailyCheckIn]
    ) -> [PsychologyEnrichedTrade] {
        let todayKey = TraderPsychologyAnalyticsFoundation.todayCheckInDateKey()
        let todayOnly = trades.filter {
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0) == todayKey
        }
        return TraderPsychologyAnalyticsEngine.enrich(trades: todayOnly, checkIns: checkIns)
    }

    func dismissPsychologyGuardrail(_ notice: PsychologyGuardrailNotice) {
        let todayKey = TraderPsychologyAnalyticsFoundation.todayCheckInDateKey()
        PsychologyGuardrailDismissStore.shared.dismiss(
            PsychologyGuardrailEngine.dedupeKey(for: notice, tradingDay: todayKey)
        )
        psychologyGuardrailNotices.removeAll { $0.id == notice.id }
    }

    private func runSecondaryHydration(
        profileID: ProfileID,
        forceNetwork: Bool,
        skipPayouts: Bool
    ) async {
        if !skipPayouts {
            await hydratePayouts(profileID: profileID, forceNetwork: forceNetwork)
        }
        await hydratePropFirmPayoutCycles(
            profileID: profileID,
            accountIDs: fundedPropAccountIDs(),
            forceNetwork: forceNetwork
        )
        await hydrateCheckIns(profileID: profileID, forceNetwork: forceNetwork)
    }

    private func fundedPropAccountIDs() -> [TradingAccountID] {
        accounts.filter { PropFirmPayoutPolicy.supportsRecordPayout(for: $0) }.map(\.id)
    }

    private func hydratePropFirmPayoutCycles(
        profileID: ProfileID,
        accountIDs: [TradingAccountID],
        forceNetwork: Bool
    ) async {
        guard !accountIDs.isEmpty else { return }

        var pending: [TradingAccountID] = []
        for accountID in accountIDs {
            if !forceNetwork,
               let cached = SessionPayoutCyclesStore.shared.cached(for: accountID, profileID: profileID)
            {
                payoutCyclesByAccount[accountID] = cached
            } else {
                pending.append(accountID)
            }
        }
        guard !pending.isEmpty else { return }

        let started = CFAbsoluteTimeGetCurrent()
        do {
            let cycles = try await trades.payoutCycleHistory(for: pending)
            var grouped: [TradingAccountID: [AccountPayoutCycle]] = [:]
            for accountID in pending {
                grouped[accountID] = []
            }
            for cycle in cycles {
                grouped[cycle.accountID, default: []].append(cycle)
            }
            for (accountID, accountCycles) in grouped {
                payoutCyclesByAccount[accountID] = accountCycles
                SessionPayoutCyclesStore.shared.seed(accountCycles, for: accountID, profileID: profileID)
            }
            PayoutBatchDiagnostics.logCycles(
                accounts: pending.count,
                requests: 1,
                cycles: cycles.count,
                dtMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            )
        } catch {
            for accountID in pending {
                payoutCyclesByAccount[accountID] = []
            }
        }
    }

    private func hydrateCheckIns(profileID: ProfileID, forceNetwork: Bool) async {
        guard let range = checkInDateRange(from: tradeInputs) else {
            recomputePsychology()
            return
        }
        if !forceNetwork,
           !SessionDailyCheckInsStore.shared.needsLoad(
               for: profileID,
               startDate: range.start,
               endDate: range.end
           )
        {
            recomputePsychology()
            return
        }
        do {
            let items: [TraderDailyCheckIn]
            if BackendV2FeatureFlags.isEnabled(.dashboard), let rpc {
                let accountID: TradingAccountID? = {
                    if case .account(let id) = accountFilter { return id }
                    return nil
                }()
                items = try await DashboardLoadProbe.measure(
                    "dashboard.checkIns.rpc",
                    kind: .network,
                    blocksFirstUsefulRender: false,
                    note: "psychology check-in window RPC"
                ) {
                    try await PsychologyCheckInBootstrapLoader.load(
                        rpc: rpc,
                        accountID: accountID
                    )
                }
            } else {
                items = try await DashboardLoadProbe.measure(
                    "dashboard.checkIns",
                    kind: .network,
                    blocksFirstUsefulRender: false,
                    note: "daily check-ins for psychology analytics"
                ) {
                    try await dailyCheckIns.checkIns(
                        for: profileID,
                        from: range.start,
                        to: range.end
                    )
                }
            }
            guard !Task.isCancelled else { return }
            let seededRange: (start: String, end: String)
            if items.isEmpty {
                seededRange = range
            } else {
                let dates = items.map(\.checkInDate)
                seededRange = (dates.min() ?? range.start, dates.max() ?? range.end)
            }
            SessionDailyCheckInsStore.shared.seed(items, for: profileID, range: seededRange)
            recomputePsychology()
        } catch {
            recomputePsychology()
        }
    }

    private func checkInDateRange(
        from inputs: [DashboardChartMetrics.Input]
    ) -> (start: String, end: String)? {
        guard !inputs.isEmpty else { return nil }
        let keys = inputs.map {
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0.trade)
        }
        guard let start = keys.min(), let end = keys.max() else { return nil }
        return (start, end)
    }

    // MARK: - Realtime (idle subscribe — no polling)

    private func startRealtime(profileID: ProfileID) async {
        guard let realtimeHub else { return }
        let channel = RealtimeChannelID(kind: .profile, topic: "dashboard:\(profileID.rawValue)")
        if watchedChannel == channel { return }
        await stopRealtime()
        watchedChannel = channel
        try? await realtimeHub.subscriptions.subscribe(channel)
        _ = await DashboardLoadProbe.measure(
            "dashboard.realtime.subscribe",
            kind: .realtime,
            blocksFirstUsefulRender: false,
            note: "registry-only until trade postgres_changes attach"
        ) { () }
    }

    private func stopRealtime() async {
        guard let realtimeHub, let channel = watchedChannel else { return }
        try? await realtimeHub.subscriptions.unsubscribe(channel)
        watchedChannel = nil
    }

    // MARK: - Dashboard GRDB-first (Phase 5F)

    @discardableResult
    private func tryPaintFromGRDBCache(profileID: ProfileID, generation: UInt64) async -> Bool {
        guard usesDashboardAnalyticsGRDB else { return false }
        let diskBlob = DashboardAnalyticsDiskCache.load(viewerID: profileID)
        let sessionAccounts =
            SessionAccountsStore.shared.cached(for: profileID)
            ?? detailCache.accounts(for: profileID)
            ?? []
        let presentation = await DashboardAnalyticsGRDBLoader.loadPresentation(
            viewerID: profileID,
            diskEnvelope: diskBlob?.payload,
            sessionAccounts: sessionAccounts
        )
        guard presentation.canRender, let bootstrap = presentation.bootstrap else {
            let reason: String = switch presentation.readState {
            case .missing: "missing"
            case .partial: "partial"
            case .stale: "stale"
            case .available: "other"
            }
            DashboardAnalyticsGRDBProbe.logFallback(reason: reason)
            return false
        }
        do {
            let applied = try DashboardAnalyticsV3Applier.apply(
                bootstrap,
                expectedViewerID: profileID.rawValue,
                detailCache: detailCache
            )
            guard generation == loadGeneration, !Task.isCancelled else { return false }
            analyticsV3Bootstrap = applied.bootstrap
            analyticsV3Revision = applied.revision
            apply(trades: [], accounts: applied.accounts, profileID: profileID)
            if let payout = applied.payoutTotal {
                payoutTotal = payout
            }
            noteTradeHistoryApplied(
                totalTradeCount: applied.bootstrap.data.aggregatePresets["all"]?.metrics.trade_count,
                historyComplete: true
            )
            hasLoaded = true
            recompute()
            phase = .loaded
            DashboardAnalyticsGRDBProbe.logRender(
                source: "grdb",
                revision: analyticsV3Revision,
                scope: accountFilterTitle,
                preset: DashboardAnalyticsMapper.presetKey(for: dateRange),
                elapsedMs: presentation.elapsedMs
            )
            DashboardLoadProbe.markFirstUsefulRender()
            if applied.payoutTotal != nil {
                DashboardLoadProbe.markFullHydration()
            }
            AuthenticatedLaunchPhasing.markCriticalVisibleSurfaceReady(tab: .home)
            #if DEBUG
            ColdLaunchSummaryProbe.markDashboardFirstRender(source: "grdb")
            #endif
            secondaryTask?.cancel()
            secondaryTask = Task { [weak self] in
                await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
                await self?.runSecondaryHydration(
                    profileID: profileID,
                    forceNetwork: false,
                    skipPayouts: applied.payoutTotal != nil
                )
            }
            if case .account(let id) = accountFilter {
                _ = await trySeedAccountChartsFromGRDB(
                    accountID: id,
                    profileID: profileID,
                    selectionToken: accountChartSelectionToken
                )
                recompute()
            } else if accountFilter == .all {
                _ = await trySeedAggregateChartsFromGRDB(
                    profileID: profileID,
                    selectionToken: aggregateChartSelectionToken
                )
                recompute()
            }
            scheduleChartHydration()
            scheduleDashboardGRDBBackgroundReconcile(profileID: profileID, generation: generation)
            await startRealtime(profileID: profileID)
            return true
        } catch {
            DashboardAnalyticsGRDBProbe.logFallback(reason: "decode_error")
            return false
        }
    }

    @discardableResult
    private func trySeedAccountChartsFromGRDB(
        accountID: TradingAccountID,
        profileID: ProfileID,
        selectionToken: UInt64
    ) async -> Bool {
        guard usesDashboardAnalyticsGRDB else { return false }
        guard selectionToken == accountChartSelectionToken else { return false }
        guard let read = await DashboardAnalyticsGRDBLoader.loadAccountCharts(
            viewerID: profileID,
            accountID: accountID,
            revision: analyticsV3Revision
        ) else {
            DashboardAnalyticsGRDBProbe.logFallback(reason: "database_error")
            return false
        }
        let stateLabel: String = switch read.state {
        case .available: "available"
        case .stale: "stale"
        case .partial: "partial"
        case .missing: "missing"
        }
        DashboardAnalyticsGRDBProbe.logAccountCharts(
            account: accountID.rawValue,
            state: stateLabel,
            revision: read.requiredRevision
        )
        guard read.state == .available, !read.presets.isEmpty else { return false }
        DashboardAnalyticsAccountChartsStore.shared.seed(
            accountID: accountID,
            revision: analyticsV3Revision,
            presets: read.presets
        )
        DashboardAnalyticsGRDBProbe.logNetworkAvoided(reason: "account_charts_local")
        return true
    }

    @discardableResult
    private func trySeedAggregateChartsFromGRDB(
        profileID: ProfileID,
        selectionToken: UInt64
    ) async -> Bool {
        guard usesDashboardAnalyticsGRDB else { return false }
        guard selectionToken == aggregateChartSelectionToken else { return false }
        guard let read = await DashboardAnalyticsGRDBLoader.loadAggregateCharts(
            viewerID: profileID,
            revision: analyticsV3Revision
        ) else {
            DashboardAnalyticsGRDBProbe.logFallback(reason: "database_error")
            return false
        }
        guard read.state == .available,
              DashboardAnalyticsChartsSupport.hasEquityPoints(read.presets)
        else { return false }
        DashboardAnalyticsAggregateChartsStore.shared.seed(
            revision: analyticsV3Revision,
            presets: read.presets
        )
        DashboardAnalyticsGRDBProbe.logNetworkAvoided(reason: "aggregate_charts_local")
        return true
    }

    private func scheduleDashboardGRDBBackgroundReconcile(profileID: ProfileID, generation: UInt64) {
        guard usesDashboardAnalyticsGRDB, !dashboardGRDBBackgroundReconcileScheduled else { return }
        dashboardGRDBBackgroundReconcileScheduled = true
        Task {
            await reconcileDashboardAnalyticsV3Background(profileID: profileID, generation: generation)
        }
    }

    private func reconcileDashboardAnalyticsV3Background(
        profileID: ProfileID,
        generation: UInt64
    ) async {
        await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
        guard usesDashboardAnalyticsV3, let rpc else { return }
        guard generation == loadGeneration, !Task.isCancelled else { return }
        let localRevision = analyticsV3Revision
        do {
            let loadResult = try await DashboardAnalyticsV3Loader.load(
                viewerID: profileID,
                rpc: rpc,
                forceNetwork: true
            )
            guard generation == loadGeneration, !Task.isCancelled else { return }
            let serverRevision = loadResult.bootstrap.data.revisionInt
            let changed = serverRevision != localRevision
            DashboardAnalyticsGRDBProbe.logReconcile(
                localRevision: localRevision,
                serverRevision: serverRevision,
                changed: changed
            )
            guard changed else { return }
            let applied = try DashboardAnalyticsV3Applier.apply(
                loadResult.bootstrap,
                expectedViewerID: profileID.rawValue,
                detailCache: detailCache
            )
            analyticsV3Bootstrap = applied.bootstrap
            analyticsV3Revision = applied.revision
            if let payout = applied.payoutTotal {
                payoutTotal = payout
            }
            recompute()
            scheduleChartHydration()
        } catch {
            // Preserve GRDB/JSON presentation when background reconcile fails.
        }
    }

    // MARK: - Format

    static func money(_ value: Decimal) -> String {
        ProfileDisplay.formatMoney(value)
    }

    static func factor(_ value: Decimal?) -> String {
        NumberDisplay.factor(value)
    }
}
