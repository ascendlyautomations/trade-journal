import Foundation
import Observation

@Observable
@MainActor
final class YearlyReportDetailViewModel: ScreenLifecycle {
    typealias State = YearlyReportDetailState

    private(set) var state = YearlyReportDetailState()

    private let year: Int
    private let tradingReports: any TradingReportRepository
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let navigationCoordinator: NavigationCoordinator
    private var bootstrapTask: Task<Void, Never>?

    init(
        year: Int,
        tradingReports: any TradingReportRepository,
        trades: any TradeRepository,
        session: any SessionProviding,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.year = year
        self.tradingReports = tradingReports
        self.trades = trades
        self.session = session
        self.navigationCoordinator = navigationCoordinator
        state.year = year
        state.filters = TradingReportSessionStore.shared.filters
    }

    var phase: YearlyReportDetailState.Phase { state.phase }
    var report: TradingYearlyReport? { state.report }
    var filters: TradingReportFilters { state.filters }
    var accounts: [TradingAccount] { state.accounts }
    var title: String { state.report?.title ?? "\(year) Performance Report" }
    var dateRangeLabel: String? { state.report?.dateRangeLabel }
    var ownerProfileID: ProfileID? { state.profileID }

    var accountsForMenu: [TradingAccount] {
        let selectedID: TradingAccountID? = {
            if case .account(let id) = state.filters.accountFilter { return id }
            return nil
        }()
        return OwnerAccountDropdownSupport.menuAccounts(
            profileID: state.profileID,
            fallback: state.accounts,
            preservingSelection: selectedID
        )
    }

    var accountFilterTitle: String {
        switch state.filters.accountFilter {
        case .all: return "All Accounts"
        case .account(let id):
            if let account = state.accounts.first(where: { $0.id == id }) {
                return TradingAccountDisplay.ownerDropdownLine(for: account)
            }
            return "Account"
        }
    }

    func bootstrapIfNeeded() async {
        guard bootstrapTask == nil, !state.didBootstrap else { return }
        bootstrapTask = Task { await performBootstrap(forceNetwork: false) }
        await bootstrapTask?.value
        bootstrapTask = nil
    }

    func refresh() async {
        var next = state
        next.isRefreshing = true
        state = next
        await performBootstrap(forceNetwork: true)
        next = state
        next.isRefreshing = false
        state = next
    }

    func retry() async { await refresh() }
    func loadMore() async {}
    func subscribeRealtime() {}
    func unsubscribeRealtime() {}

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        ExperienceHaptics.play(.selection)
        var next = state
        next.filters.accountFilter = filter
        state = next
        TradingReportSessionStore.shared.filters.accountFilter = filter
        Task { await reloadReport(forceNetwork: false) }
    }

    func setAccountMode(_ mode: ProfileStatisticsMetrics.Mode) {
        ExperienceHaptics.play(.selection)
        var next = state
        next.filters.accountMode = mode
        state = next
        TradingReportSessionStore.shared.filters.accountMode = mode
        Task { await reloadReport(forceNetwork: false) }
    }

    func openManageAccounts() {
        navigationCoordinator.pushHome(.settings(.tradingAccounts))
    }

    func openMonth(_ ref: TradingReportMonthRef) {
        ExperienceHaptics.play(.selection)
        TradingReportSessionStore.shared.filters = state.filters
        ReportsNavigation.openDetail(ref.reportID, using: navigationCoordinator)
    }

    private func performBootstrap(forceNetwork: Bool) async {
        if !state.didBootstrap {
            var loading = state
            loading.phase = .loading
            state = loading
        }

        if let userID = await session.currentUserID {
            state.profileID = ProfileID(userID.rawValue)
        }

        await loadAccountsIfNeeded()
        await reloadReport(forceNetwork: forceNetwork)
    }

    private func loadAccountsIfNeeded() async {
        guard state.accounts.isEmpty, let profileID = state.profileID else { return }
        do {
            let loaded = try await trades.accounts(for: profileID)
            var next = state
            next.accounts = loaded.filter(\.isActive)
            state = next
        } catch {
            // Account menu falls back to all accounts only.
        }
    }

    private func reloadReport(forceNetwork: Bool) async {
        do {
            let report = try await tradingReports.yearlyReport(
                for: year,
                filters: state.filters,
                forceNetwork: forceNetwork
            )
            var next = state
            next.report = report
            next.didBootstrap = true
            next.phase = .loaded
            next.lastUpdated = Date()
            state = next
        } catch {
            var next = state
            next.phase = .failed(ReportsScreenViewModel.userFacingMessage(for: error))
            state = next
        }
    }
}

struct YearlyReportDetailState {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var phase: Phase = .idle
    var year: Int?
    var report: TradingYearlyReport?
    var filters: TradingReportFilters = TradingReportFilters()
    var accounts: [TradingAccount] = []
    var profileID: ProfileID?
    var didBootstrap = false
    var isRefreshing = false
    var lastUpdated: Date?
}

extension YearlyReportDetailState: ScreenStateModeling {
    var screenPhase: ScreenPhase {
        switch phase {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded: return .loaded
        case .failed(let message): return .failed(message)
        }
    }

    var screenErrorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    var pagination: ScreenPaginationSnapshot { .none }
}
