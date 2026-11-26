import Foundation
import Observation

@Observable
@MainActor
final class BacktestLabViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let tradeDetailRepository: any TradeDetailRepository
    private let navigationCoordinator: NavigationCoordinator
    let loadsTraxsProPreviewSampleOnly: Bool

    private(set) var phase: Phase = .idle
    private(set) var allTrades: [Trade] = []
    private(set) var accounts: [TradingAccount] = []
    private(set) var accountNames: [TradingAccountID: String] = [:]
    var accountFilter: DashboardAccountFilter = .all
    var selectedStrategy = BacktestLabMetrics.allStrategiesToken
    var timeFilter: BacktestLabTimeFilter = .allTime
    var customTimeInterval: DateInterval?
    var showsCustomTimeSheet = false
    var draftCustomRangeStart: Date?
    var draftCustomRangeEnd: Date?
    var pendingDelete: TradeOwnerJournalSummary?
    var journalSharePresentation: JournalTradeShareSupport.Presentation?

    private(set) var dashboardSummary: DashboardChartMetrics.Summary?
    private(set) var insightsPresentation = DashboardInsightsPresentation(
        isLoading: false,
        performance: [],
        advancedEdge: [],
        riskBehavior: []
    )
    private(set) var metricChips: [DashboardMetricChip] = []
    private(set) var performanceCards: [DashboardMetricChip] = []
    private(set) var equityChartPoints: [ProfileStatisticsMetrics.EquityPoint] = []
    private(set) var equityHeroTitle = "Equity"
    private(set) var equityHeroDisplayValue: Decimal = 0
    private(set) var equityHeroPeriodChangePercent: Decimal?
    private(set) var strategyLeaderboard: [BacktestLabGroupRow] = []
    private(set) var setupTagLeaderboard: [BacktestLabGroupRow] = []
    private(set) var instrumentLeaderboard: [BacktestLabGroupRow] = []
    var activeDrillDown: BacktestLabChartDrillDown?
    var showsEquityDrawdownSettings = false
    var equityDrawdownLimitDraft = ""
    var equityDrawdownFloorCapDraft = ""
    var equityDrawdownTypeDraft: LivePersonalDrawdownType = .fixed
    var equityDrawdownSettingsError: String?
    private(set) var isSavingEquityDrawdownSettings = false

    private var profileID: ProfileID?
    private var loadTask: Task<Void, Never>?
    private var analyticsTask: Task<Void, Never>?

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        tradeDetailRepository: any TradeDetailRepository,
        navigationCoordinator: NavigationCoordinator,
        loadsTraxsProPreviewSampleOnly: Bool = false
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.tradeDetailRepository = tradeDetailRepository
        self.navigationCoordinator = navigationCoordinator
        self.loadsTraxsProPreviewSampleOnly = loadsTraxsProPreviewSampleOnly
    }

    var strategyOptions: [String] {
        [BacktestLabMetrics.allStrategiesToken] + BacktestLabMetrics.distinctStrategies(in: allTrades)
    }

    private var backtestModeAccountIDScope: Set<TradingAccountID> {
        BacktestLabFilters.backtestModeAccountIDs(from: accounts)
    }

    var scopedTrades: [Trade] {
        BacktestLabFilters.apply(
            allTrades,
            accountFilter: accountFilter,
            strategy: BacktestLabMetrics.allStrategiesToken,
            timeFilter: timeFilter,
            customInterval: customTimeInterval,
            backtestModeAccountIDs: backtestModeAccountIDScope,
            copyTradingGroups: []
        )
    }

    var filteredTrades: [Trade] {
        BacktestLabFilters.apply(
            allTrades,
            accountFilter: accountFilter,
            strategy: selectedStrategy,
            timeFilter: timeFilter,
            customInterval: customTimeInterval,
            backtestModeAccountIDs: backtestModeAccountIDScope,
            copyTradingGroups: []
        )
    }

    var lifetimeScopedTrades: [Trade] {
        BacktestLabFilters.lifetimeScopedTrades(
            allTrades,
            accountFilter: accountFilter,
            strategy: selectedStrategy,
            backtestModeAccountIDs: backtestModeAccountIDScope
        )
    }

    var journalItems: [TradeOwnerJournalSummary] {
        filteredTrades.map(TradeSummaryMapper.ownerJournal(fromListTrade:))
    }

    var metrics: BacktestLabMetrics.Snapshot {
        BacktestLabMetrics.snapshot(for: filteredTrades)
    }

    var selectedAccount: TradingAccount? {
        guard case .account(let id) = accountFilter else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    var backtestEligibleAccounts: [TradingAccount] {
        BacktestLabFilters.eligibleBacktestAccounts(accounts)
    }

    var canConfigureEquityDrawdownSettings: Bool {
        selectedAccount?.mode == .backtest
    }

    var drillDownJournalItems: [TradeOwnerJournalSummary] {
        guard let activeDrillDown else { return [] }
        return activeDrillDown.filter(filteredTrades).map(TradeSummaryMapper.ownerJournal(fromListTrade:))
    }

    var strategyBreakdown: [BacktestLabMetrics.StrategyBreakdown] {
        let pool = selectedStrategy == BacktestLabMetrics.allStrategiesToken
            ? scopedTrades
            : filteredTrades
        return BacktestLabMetrics.strategyBreakdown(from: pool)
    }

    var strategyMenuTitle: String {
        selectedStrategy == BacktestLabMetrics.allStrategiesToken ? "All Strategies" : selectedStrategy
    }

    var timeMenuTitle: String {
        BacktestLabFilters.compactTimeLabel(
            timeFilter: timeFilter,
            customInterval: customTimeInterval
        )
    }

    var accountMenuTitle: String {
        OwnerAccountFilterMenuSupport.menuTitle(
            filter: accountFilter,
            accounts: BacktestLabFilters.eligibleBacktestAccounts(accounts),
            profileID: profileID
        )
    }

    var ownerAccountsProfileID: ProfileID? { profileID }

    var backtestAccountsForMenu: [TradingAccount] {
        let eligible = BacktestLabFilters.eligibleBacktestAccounts(accounts)
        let selectedID: TradingAccountID? = {
            if case .account(let id) = accountFilter { return id }
            return nil
        }()
        let menu = OwnerAccountDropdownSupport.menuAccounts(
            profileID: profileID,
            fallback: eligible,
            preservingSelection: selectedID
        )
        return BacktestLabFilters.eligibleBacktestAccounts(menu)
    }

    var canApplyCustomTimeRange: Bool {
        guard let start = draftCustomRangeStart, let end = draftCustomRangeEnd else { return false }
        return start <= end
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded || allTrades.isEmpty else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        await performLoad(force: true)
    }

    func setStrategy(_ strategy: String) {
        guard selectedStrategy != strategy else { return }
        ExperienceHaptics.play(.selection)
        selectedStrategy = strategy
        refreshAnalytics()
    }

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        let eligible = BacktestLabFilters.eligibleBacktestAccounts(accounts)
        let resolved = OwnerAccountMutationSync.reconciledAccountFilter(
            filter,
            accounts: eligible,
            profileID: profileID
        )
        let sanitized = BacktestLabFilters.sanitizedAccountFilter(resolved, eligibleAccounts: eligible)
        guard accountFilter != sanitized else { return }
        ExperienceHaptics.play(.selection)
        accountFilter = sanitized
        refreshAnalytics()
    }

    func setTimeFilter(_ filter: BacktestLabTimeFilter) {
        guard filter != .custom else {
            openCustomTimeRangeEditor()
            return
        }
        guard timeFilter != filter else { return }
        ExperienceHaptics.play(.selection)
        timeFilter = filter
        customTimeInterval = nil
        refreshAnalytics()
    }

    func openCustomTimeRangeEditor() {
        if let customTimeInterval {
            draftCustomRangeStart = customTimeInterval.start
            draftCustomRangeEnd = customTimeInterval.end
        } else {
            let end = Date()
            draftCustomRangeEnd = end
            draftCustomRangeStart = Calendar.current.date(byAdding: .day, value: -7, to: end)
        }
        showsCustomTimeSheet = true
    }

    func applyCustomTimeRange() {
        guard let start = draftCustomRangeStart, let end = draftCustomRangeEnd, start <= end else { return }
        customTimeInterval = DashboardScopeFilterSupport.normalizedCustomInterval(start: start, end: end)
        timeFilter = .custom
        ExperienceHaptics.play(.selection)
        refreshAnalytics()
    }

    func refreshAnalytics() {
        analyticsTask?.cancel()
        let periodTrades = filteredTrades
        let lifetimeTrades = lifetimeScopedTrades
        let accountFilter = accountFilter
        let accounts = backtestEligibleAccounts
        let selected = selectedAccount
        let timeFilter = timeFilter
        let customInterval = customTimeInterval
        analyticsTask = Task { [weak self] in
            let summary = BacktestLabAnalyticsSupport.computePeriodSummary(from: periodTrades)
            let realizedRr = BacktestLabAnalyticsSupport.averageRealizedRr(for: periodTrades)
            let payoff = BacktestLabAnalyticsSupport.payoffRatio(
                avgWin: summary.avgWin,
                avgLoss: summary.avgLoss
            )
            let chips = BacktestLabAnalyticsSupport.metricChips(summary: summary)
            let performance = BacktestLabAnalyticsSupport.performanceCards(
                summary: summary,
                averageRealizedRr: realizedRr,
                payoff: payoff
            )
            let insights = BacktestLabAnalyticsSupport.insightsPresentation(
                summary: summary,
                periodTrades: periodTrades,
                isLoading: false
            )
            let chartPoints = BacktestLabEquitySupport.resolveChartPoints(
                accountFilter: accountFilter,
                selectedAccount: selected,
                backtestAccounts: accounts,
                lifetimeTrades: lifetimeTrades,
                timeFilter: timeFilter,
                customTimeInterval: customInterval
            )
            let hero = BacktestLabEquitySupport.headlinePresentation(
                accountFilter: accountFilter,
                selectedAccount: selected,
                periodSummary: summary,
                lifetimeTrades: lifetimeTrades,
                timeFilter: timeFilter,
                customTimeInterval: customInterval
            )
            let strategyRows = BacktestLabGroupedPerformance.strategyRows(from: periodTrades)
            let setupRows = BacktestLabGroupedPerformance.setupTagRows(from: periodTrades)
            let instrumentRows = BacktestLabGroupedPerformance.instrumentRows(from: periodTrades)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.dashboardSummary = summary
                self.metricChips = chips
                self.performanceCards = performance
                self.insightsPresentation = insights
                self.equityChartPoints = chartPoints
                self.equityHeroTitle = hero.title
                self.equityHeroDisplayValue = hero.displayEquity
                self.equityHeroPeriodChangePercent = hero.periodChangePercent
                self.strategyLeaderboard = strategyRows
                self.setupTagLeaderboard = setupRows
                self.instrumentLeaderboard = instrumentRows
            }
        }
    }

    func openEquityDrawdownSettings() {
        guard let account = selectedAccount, account.mode == .backtest else { return }
        let draft = LivePersonalDrawdownEngine.gearDraft(
            from: account,
            eligibility: .backtestAccount
        )
        equityDrawdownLimitDraft = draft.limitDigits
        equityDrawdownFloorCapDraft = draft.floorCapDigits
        equityDrawdownTypeDraft = draft.limitType
        equityDrawdownSettingsError = nil
        showsEquityDrawdownSettings = true
    }

    func cancelEquityDrawdownSettings() {
        showsEquityDrawdownSettings = false
        equityDrawdownSettingsError = nil
    }

    func saveEquityDrawdownSettings() async {
        guard let account = selectedAccount else { return }
        var owner = profileID
        if owner == nil, let userID = await session.currentUserID {
            owner = ProfileID(userID.rawValue)
        }
        guard let owner else { return }
        isSavingEquityDrawdownSettings = true
        defer { isSavingEquityDrawdownSettings = false }
        switch LivePersonalDrawdownEngine.parseGearDraft(
            limitDigits: equityDrawdownLimitDraft,
            limitType: equityDrawdownTypeDraft,
            floorCapDigits: equityDrawdownFloorCapDraft,
            includeFloorCapField: equityDrawdownTypeDraft == .trailing,
            limitPolicy: .clearWhenEmptyOrZero
        ) {
        case .failure(let error):
            equityDrawdownSettingsError = error.message
            return
        case .success(let parsedConfig):
            if parsedConfig != nil,
               TradingAccountStartingBalancePolicy.resolvedStartingBalance(for: account) == nil
            {
                equityDrawdownSettingsError = TradingAccountStartingBalancePolicy.liveLedgerMessage
                return
            }
            do {
                let updated = try await trades.updateLivePersonalDrawdownConfig(
                    id: account.id,
                    ownerID: owner,
                    config: parsedConfig
                )
                if let index = accounts.firstIndex(where: { $0.id == updated.id }) {
                    accounts[index] = updated
                }
                showsEquityDrawdownSettings = false
                equityDrawdownSettingsError = nil
                refreshAnalytics()
                ExperienceHaptics.play(.success)
            } catch {
                equityDrawdownSettingsError = ProfileSectionSupport.message(for: error)
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func browseWins() { presentDrillDown(.wins) }
    func browseLosses() { presentDrillDown(.losses) }
    func browseSession(_ label: String) { presentDrillDown(.session(label)) }
    func browseWeekday(label: String) { presentDrillDown(.weekday(label)) }
    func browseHour(label: String) { presentDrillDown(.hour(label)) }
    func browseLong() { presentDrillDown(.long) }
    func browseShort() { presentDrillDown(.short) }
    func browseHoldBucket(label: String) { presentDrillDown(.holdBucket(label)) }
    func browseStrategy(key: String) { presentDrillDown(.strategy(key)) }
    func browseSetupTag(key: String) { presentDrillDown(.setupTag(key)) }
    func browseInstrument(key: String) { presentDrillDown(.instrument(key)) }

    private func presentDrillDown(_ drillDown: BacktestLabChartDrillDown) {
        guard !loadsTraxsProPreviewSampleOnly else { return }
        ExperienceHaptics.play(.selection)
        activeDrillDown = drillDown
    }

    func dismissDrillDown() {
        activeDrillDown = nil
    }

    func openManageAccounts() {
        guard !loadsTraxsProPreviewSampleOnly else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushHome(.settings(.tradingAccounts))
    }

    func openCalendar() {
        ExperienceHaptics.play(.selection)
        BacktestCalendarSessionStore.shared.publish(
            accountFilter: accountFilter,
            selectedStrategy: selectedStrategy,
            backtestModeAccountIDs: backtestModeAccountIDScope
        )
        navigationCoordinator.pushHome(.backtestCalendar)
    }

    func handleAccountMutation() {
        guard let profileID else { return }
        guard let loaded = OwnerAccountMutationSync.sessionAccounts(
            profileID: profileID,
            detailCache: detailCache
        ) else { return }
        accounts = loaded
        accountNames = OwnerAccountMutationSync.accountNamesMap(from: loaded)
        OwnerAccountMutationSync.seedDetailCacheIfNeeded(loaded, profileID: profileID, detailCache: detailCache)
        let eligible = BacktestLabFilters.eligibleBacktestAccounts(loaded)
        let sanitized = BacktestLabFilters.sanitizedAccountFilter(accountFilter, eligibleAccounts: eligible)
        if sanitized != accountFilter {
            accountFilter = sanitized
        }
        refreshAnalytics()
    }

    func handleCopyTradingGroupsMutation() {
        guard let profileID else { return }
        let eligible = BacktestLabFilters.eligibleBacktestAccounts(accounts)
        let resolved = OwnerAccountMutationSync.reconciledAccountFilter(
            accountFilter,
            accounts: eligible,
            profileID: profileID
        )
        let sanitized = BacktestLabFilters.sanitizedAccountFilter(resolved, eligibleAccounts: eligible)
        guard accountFilter != sanitized else { return }
        accountFilter = sanitized
        refreshAnalytics()
    }

    func openTrade(_ item: TradeOwnerJournalSummary) {
        ExperienceHaptics.play(.selection)
        detailCache.seedPresentationSeed(TradeSummaryMapper.presentationSeed(from: item))
        if let accountID = item.accountID, let name = accountNames[accountID] {
            detailCache.seedAccountName(name, for: accountID)
        }
        navigationCoordinator.open(.home(.tradeDetail(item.id)))
    }

    func editTrade(_ item: TradeOwnerJournalSummary) {
        guard !loadsTraxsProPreviewSampleOnly else { return }
        ExperienceHaptics.play(.selection)
        Task {
            do {
                _ = try await tradeDetailRepository.load(tradeID: item.id, policy: .default)
                navigationCoordinator.editTrade(item.id)
            } catch {
                phase = .failed(ProfileSectionSupport.message(for: error))
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func shareTrade(_ item: TradeOwnerJournalSummary) {
        guard !loadsTraxsProPreviewSampleOnly else { return }
        ExperienceHaptics.play(.selection)
        journalSharePresentation = JournalTradeShareSupport.presentation(for: item.summary)
    }

    func requestDelete(_ item: TradeOwnerJournalSummary) {
        guard !loadsTraxsProPreviewSampleOnly else { return }
        ExperienceHaptics.play(.warning)
        TradeDeleteConfirmationPresenter.scheduleConfirmation { [weak self] in
            self?.pendingDelete = item
        }
    }

    func confirmDelete(item explicitItem: TradeOwnerJournalSummary? = nil) async {
        let item = explicitItem ?? pendingDelete
        guard let item else { return }
        pendingDelete = nil
        let previous = TradeSummaryMapper.listMatchTrade(from: item)
        let removedIndex = allTrades.firstIndex { $0.id == item.id }
        let removed = removedIndex.map { allTrades[$0] }
        allTrades.removeAll { $0.id == item.id }
        do {
            let owner: ProfileID
            if let profileID {
                owner = profileID
            } else if let userID = await session.currentUserID {
                owner = ProfileID(userID.rawValue)
            } else {
                throw AppError.domain(.permission(.notAuthenticated))
            }
            try await OwnerTradeDeletionService.deleteOwnedTrade(
                tradeID: item.id,
                owner: owner,
                previous: previous,
                trades: trades,
                session: session,
                detailCache: detailCache,
                tradeDetailRepository: tradeDetailRepository
            )
            refreshAnalytics()
            ExperienceHaptics.play(.success)
        } catch {
            if let removedIndex, let removed {
                allTrades.insert(removed, at: min(removedIndex, allTrades.count))
            }
            phase = .failed(ProfileSectionSupport.message(for: error))
            ExperienceHaptics.play(.warning)
        }
    }

    func displayAccountTitle(for accountID: TradingAccountID?) -> String? {
        guard let accountID else { return nil }
        return accountNames[accountID]
    }

    private func performLoad(force: Bool = false) async {
        if !force, phase == .loaded, !allTrades.isEmpty {
            loadTask = nil
            return
        }
        phase = .loading
        defer { loadTask = nil }
        do {
            guard let viewer = await session.currentUserID else {
                phase = .failed("Sign in to view Backtest Lab.")
                return
            }
            let profileID = ProfileID(viewer.rawValue)
            self.profileID = profileID
            let loaded: [Trade]
            let accountList: [TradingAccount]
            if loadsTraxsProPreviewSampleOnly {
                loaded = BacktestLabPreviewSampleData.trades(owner: profileID)
                accountList = BacktestLabPreviewSampleData.accounts(owner: profileID)
            } else {
                async let backtests = trades.backtestLabTrades(ownedBy: profileID)
                async let loadedAccounts = trades.accounts(for: profileID)
                loaded = try await backtests
                accountList = try await loadedAccounts
            }
            self.accounts = accountList
            accountNames = Dictionary(uniqueKeysWithValues: accountList.map { ($0.id, $0.name) })
            allTrades = loaded
            let eligible = BacktestLabFilters.eligibleBacktestAccounts(accountList)
            accountFilter = BacktestLabFilters.sanitizedAccountFilter(accountFilter, eligibleAccounts: eligible)
            phase = .loaded
            refreshAnalytics()
        } catch {
            phase = .failed(ProfileSectionSupport.message(for: error))
        }
    }
}
