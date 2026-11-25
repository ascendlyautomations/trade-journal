import Foundation
import Observation

@Observable
@MainActor
final class BacktestCalendarViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    let loadsTraxsProPreviewSampleOnly: Bool

    private(set) var phase: Phase = .idle
    private(set) var allTrades: [Trade] = []
    private(set) var accounts: [TradingAccount] = []
    var accountFilter: DashboardAccountFilter = .all
    var selectedStrategy = BacktestLabMetrics.allStrategiesToken
    var calendarMonth = CalendarMonthID.current()

    private var profileID: ProfileID?
    private var loadTask: Task<Void, Never>?

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        loadsTraxsProPreviewSampleOnly: Bool = false
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.loadsTraxsProPreviewSampleOnly = loadsTraxsProPreviewSampleOnly
    }

    var strategyOptions: [String] {
        [BacktestLabMetrics.allStrategiesToken] + BacktestLabMetrics.distinctStrategies(in: allTrades)
    }

    var filteredTrades: [Trade] {
        BacktestLabFilters.apply(
            allTrades,
            accountFilter: accountFilter,
            strategy: selectedStrategy,
            timeFilter: .allTime,
            customInterval: nil,
            backtestModeAccountIDs: BacktestLabFilters.backtestModeAccountIDs(from: accounts)
        )
    }

    var month: TradingCalendarMonth {
        BacktestLabCalendarSupport.buildMonth(
            year: calendarMonth.year,
            month: calendarMonth.month,
            trades: filteredTrades
        )
    }

    var strategyMenuTitle: String {
        selectedStrategy == BacktestLabMetrics.allStrategiesToken ? "All Strategies" : selectedStrategy
    }

    var accountMenuTitle: String {
        switch accountFilter {
        case .all:
            return "All Accounts"
        case .account(let id):
            if let account = accounts.first(where: { $0.id == id }) {
                return TradingAccountDisplay.ownerDropdownLine(for: account)
            }
            return "Account"
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

    func loadIfNeeded() {
        accountFilter = BacktestCalendarSessionStore.shared.accountFilter
        selectedStrategy = BacktestCalendarSessionStore.shared.selectedStrategy
        guard loadTask == nil, phase != .loaded || allTrades.isEmpty else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        await performLoad(force: true)
    }

    func syncSessionStore() {
        BacktestCalendarSessionStore.shared.publish(
            accountFilter: accountFilter,
            selectedStrategy: selectedStrategy,
            backtestModeAccountIDs: BacktestLabFilters.backtestModeAccountIDs(from: accounts)
        )
    }

    func setStrategy(_ strategy: String) {
        guard selectedStrategy != strategy else { return }
        ExperienceHaptics.play(.selection)
        selectedStrategy = strategy
        syncSessionStore()
    }

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        guard accountFilter != filter else { return }
        ExperienceHaptics.play(.selection)
        accountFilter = filter
        syncSessionStore()
    }

    func openManageAccounts() {
        guard !loadsTraxsProPreviewSampleOnly else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushHome(.settings(.tradingAccounts))
    }

    func goToPreviousMonth() {
        ExperienceHaptics.play(.selection)
        calendarMonth = calendarMonth.advancing(by: -1)
    }

    func goToNextMonth() {
        ExperienceHaptics.play(.selection)
        calendarMonth = calendarMonth.advancing(by: 1)
    }

    func goToCurrentMonth() {
        ExperienceHaptics.play(.selection)
        calendarMonth = .current()
    }

    func selectDay(_ dayKey: String) {
        ExperienceHaptics.play(.selection)
        syncSessionStore()
        navigationCoordinator.pushHome(.backtestTradingDay(dayKey))
    }

    func handleAccountMutation() {
        guard let profileID else { return }
        guard let loaded = OwnerAccountMutationSync.sessionAccounts(
            profileID: profileID,
            detailCache: detailCache
        ) else { return }
        accounts = loaded
        OwnerAccountMutationSync.seedDetailCacheIfNeeded(loaded, profileID: profileID, detailCache: detailCache)
        let eligible = BacktestLabFilters.eligibleBacktestAccounts(loaded)
        let sanitized = BacktestLabFilters.sanitizedAccountFilter(accountFilter, eligibleAccounts: eligible)
        if sanitized != accountFilter {
            accountFilter = sanitized
            syncSessionStore()
        }
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
                phase = .failed("Sign in to view Backtest Calendar.")
                return
            }
            let profileID = ProfileID(viewer.rawValue)
            self.profileID = profileID
            if loadsTraxsProPreviewSampleOnly {
                allTrades = BacktestLabPreviewSampleData.trades(owner: profileID)
                accounts = BacktestLabPreviewSampleData.accounts(owner: profileID)
            } else {
                async let backtests = trades.backtestLabTrades(ownedBy: profileID)
                async let loadedAccounts = trades.accounts(for: profileID)
                allTrades = try await backtests
                accounts = try await loadedAccounts
            }
            syncSessionStore()
            phase = .loaded
        } catch {
            phase = .failed(ProfileSectionSupport.message(for: error))
        }
    }
}