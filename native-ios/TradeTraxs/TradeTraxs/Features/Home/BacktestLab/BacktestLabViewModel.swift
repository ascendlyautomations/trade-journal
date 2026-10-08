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
    private(set) var accountNames: [TradingAccountID: String] = [:]
    var selectedStrategy = BacktestLabMetrics.allStrategiesToken
    var calendarMonth = CalendarMonthID.current()
    var pendingDelete: TradeOwnerJournalSummary?
    var sharePayload: SharePayload?

    struct SharePayload: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

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

    var filteredTrades: [Trade] {
        BacktestLabMetrics.filter(allTrades, strategy: selectedStrategy)
    }

    var journalItems: [TradeOwnerJournalSummary] {
        filteredTrades.map(TradeSummaryMapper.ownerJournal(fromListTrade:))
    }

    var metrics: BacktestLabMetrics.Snapshot {
        BacktestLabMetrics.snapshot(for: filteredTrades)
    }

    var strategyBreakdown: [BacktestLabMetrics.StrategyBreakdown] {
        let pool = selectedStrategy == BacktestLabMetrics.allStrategiesToken
            ? allTrades
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
        let summary = item.summary
        let pnl = TradeDisplay.pnlText(summary.realizedPnL)
        let side = summary.side == .long ? "Long" : "Short"
        sharePayload = SharePayload(text: "\(summary.symbol.ticker) \(side) \(pnl) · Backtest Lab")
    }

    func requestDelete(_ item: TradeOwnerJournalSummary) {
        ExperienceHaptics.play(.warning)
        TradeDeleteConfirmationPresenter.scheduleConfirmation { [weak self] in
            self?.pendingDelete = item
        }
    }

    func confirmDelete() async {
        guard let item = pendingDelete else { return }
        pendingDelete = nil
        do {
            try await trades.delete(id: item.id)
            allTrades.removeAll { $0.id == item.id }
            if let owner = profileID {
                TradeJournalMutationStore.shared.noteDeleted(id: item.id, owner: owner)
            }
            ExperienceHaptics.play(.success)
        } catch {
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
            async let accounts = trades.accounts(for: profileID)
            let loaded = try await backtests
            let accountList = try await accounts
            accountNames = Dictionary(uniqueKeysWithValues: accountList.map { ($0.id, $0.name) })
            allTrades = loaded
            phase = .loaded
        } catch {
            phase = .failed(ProfileSectionSupport.message(for: error))
        }
    }
}
