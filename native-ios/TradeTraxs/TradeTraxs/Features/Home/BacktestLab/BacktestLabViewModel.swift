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
    var calendarMonth = CalendarMonthID.current()
    var pendingDelete: TradeOwnerJournalSummary?
    var journalSharePresentation: JournalTradeShareSupport.Presentation?

    private var profileID: ProfileID?
    private var loadTask: Task<Void, Never>?

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        tradeDetailRepository: any TradeDetailRepository,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.tradeDetailRepository = tradeDetailRepository
        self.navigationCoordinator = navigationCoordinator
    }

    var strategyOptions: [String] {
        [BacktestLabMetrics.allStrategiesToken] + BacktestLabMetrics.distinctStrategies(in: allTrades)
    }

    var scopedTrades: [Trade] {
        BacktestLabFilters.apply(
            allTrades,
            accountFilter: accountFilter,
            strategy: BacktestLabMetrics.allStrategiesToken,
            timeFilter: timeFilter,
            customInterval: customTimeInterval
        )
    }

    var filteredTrades: [Trade] {
        BacktestLabFilters.apply(
            allTrades,
            accountFilter: accountFilter,
            strategy: selectedStrategy,
            timeFilter: timeFilter,
            customInterval: customTimeInterval
        )
    }

    var journalItems: [TradeOwnerJournalSummary] {
        filteredTrades.map(TradeSummaryMapper.ownerJournal(fromListTrade:))
    }

    var metrics: BacktestLabMetrics.Snapshot {
        BacktestLabMetrics.snapshot(for: filteredTrades)
    }

    var strategyBreakdown: [BacktestLabMetrics.StrategyBreakdown] {
        let pool = selectedStrategy == BacktestLabMetrics.allStrategiesToken
            ? scopedTrades
            : filteredTrades
        return BacktestLabMetrics.strategyBreakdown(from: pool)
    }

    var calendarMonthModel: TradingCalendarMonth? {
        guard !filteredTrades.isEmpty else { return nil }
        return BacktestLabCalendarSupport.buildMonth(
            year: calendarMonth.year,
            month: calendarMonth.month,
            trades: filteredTrades
        )
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
        switch accountFilter {
        case .all:
            return "All Accounts"
        case .account(let id):
            if let account = accounts.first(where: { $0.id == id }) {
                return TradingAccountDisplay.ownerDropdownLine(for: account)
            }
            return displayAccountTitle(for: id) ?? "Account"
        }
    }

    var ownerAccountsProfileID: ProfileID? { profileID }

    var backtestAccountsForMenu: [TradingAccount] {
        let eligible = BacktestLabFilters.eligibleBacktestAccounts(accounts)
        let selectedID: TradingAccountID? = {
            if case .account(let id) = accountFilter { return id }
            return nil
        }()
        return OwnerAccountDropdownSupport.menuAccounts(
            profileID: profileID,
            fallback: eligible,
            preservingSelection: selectedID
        )
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
    }

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        guard accountFilter != filter else { return }
        ExperienceHaptics.play(.selection)
        accountFilter = filter
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
    }

    func openManageAccounts() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushHome(.settings(.tradingAccounts))
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
        let sanitized = OwnerAccountMutationSync.reconciledAccountFilter(accountFilter, accounts: loaded)
        if sanitized != accountFilter {
            accountFilter = sanitized
        }
    }

    func shiftCalendarMonth(by delta: Int) {
        ExperienceHaptics.play(.selection)
        calendarMonth = calendarMonth.advancing(by: delta)
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
        ExperienceHaptics.play(.selection)
        journalSharePresentation = JournalTradeShareSupport.presentation(for: item.summary)
    }

    func requestDelete(_ item: TradeOwnerJournalSummary) {
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
            async let backtests = trades.backtestLabTrades(ownedBy: profileID)
            async let loadedAccounts = trades.accounts(for: profileID)
            let loaded = try await backtests
            let accountList = try await loadedAccounts
            self.accounts = accountList
            accountNames = Dictionary(uniqueKeysWithValues: accountList.map { ($0.id, $0.name) })
            allTrades = loaded
            phase = .loaded
        } catch {
            phase = .failed(ProfileSectionSupport.message(for: error))
        }
    }
}
