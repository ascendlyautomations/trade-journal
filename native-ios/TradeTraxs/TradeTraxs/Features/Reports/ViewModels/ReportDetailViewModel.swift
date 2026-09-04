import Foundation
import Observation

/// Report Detail — renders the web-parity ``TradingReport`` payload.
@Observable
@MainActor
final class ReportDetailViewModel: ScreenLifecycle {
    typealias State = ReportDetailState

    private(set) var state = ReportDetailState()

    private let periodKey: TradingReportPeriodKey
    private let monthRef: TradingReportMonthRef?
    private let tradingReports: any TradingReportRepository
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private var bootstrapTask: Task<Void, Never>?

    init(
        reportID: ReportID,
        tradingReports: any TradingReportRepository,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator
    ) {
        if let monthRef = TradingReportMonthRef.parse(reportID: reportID) {
            self.monthRef = monthRef
            self.periodKey = .monthlyThis
        } else {
            self.monthRef = nil
            self.periodKey = TradingReportPeriodKey(rawValue: reportID.rawValue) ?? .weeklyThis
        }
        self.tradingReports = tradingReports
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        state.periodKey = periodKey
    }

    init(
        periodKey: TradingReportPeriodKey,
        tradingReports: any TradingReportRepository,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.monthRef = nil
        self.periodKey = periodKey
        self.tradingReports = tradingReports
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        state.periodKey = periodKey
    }

    // MARK: - Facades

    var phase: ReportDetailState.Phase { state.phase }
    var report: TradingReport? { state.report }
    var blocks: [TradingReportDetailBlock] { state.blocks }
    var bestTrade: ReportDetailState.BestTradeReference? { state.bestTrade }
    var title: String { state.report?.title ?? periodKey.kind.title }
    var dateRangeLabel: String? { state.report?.dateRangeLabel }
    var errorMessage: String? { state.screenErrorMessage }

    // MARK: - Lifecycle

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

    func retry() async {
        await refresh()
    }

    func loadMore() async {}
    func subscribeRealtime() {}
    func unsubscribeRealtime() {}

    // MARK: - Best Trade

    func openBestTrade() {
        guard case .available(let trade) = state.bestTrade else { return }
        ExperienceHaptics.play(.selection)
        detailCache.seed(trade)
        navigationCoordinator.open(.home(.tradeDetail(trade.id)))
    }

    // MARK: - Private

    private func performBootstrap(forceNetwork: Bool) async {
        if !state.didBootstrap || state.report == nil {
            var loading = state
            loading.phase = .loading
            loading.errorMessage = nil
            state = loading
        }

        do {
            let result: ReportDetailBootstrap.Result
            if let monthRef {
                result = try await ReportDetailBootstrap.loadMonth(
                    ReportDetailBootstrap.MonthContext(
                        monthRef: monthRef,
                        filters: TradingReportSessionStore.shared.filters,
                        tradingReports: tradingReports,
                        forceNetwork: forceNetwork
                    )
                )
            } else {
                result = try await ReportDetailBootstrap.load(
                    ReportDetailBootstrap.Context(
                        periodKey: periodKey,
                        tradingReports: tradingReports,
                        forceNetwork: forceNetwork
                    )
                )
            }
            var next = state
            next.report = result.report
            next.blocks = result.blocks
            next.lastUpdated = result.loadedAt
            next.didBootstrap = true
            next.phase = .loaded
            next.errorMessage = nil
            state = next
            await resolveBestTrade(from: result.report)
        } catch {
            var next = state
            next.phase = .failed(ReportsScreenViewModel.userFacingMessage(for: error))
            next.errorMessage = ReportsScreenViewModel.userFacingMessage(for: error)
            state = next
        }
    }

    /// Cache → session owner trades → single-trade fetch. Never surfaces raw IDs.
    private func resolveBestTrade(from report: TradingReport) async {
        guard let raw = report.bestTradeId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            var next = state
            next.bestTrade = nil
            state = next
            return
        }

        let tradeID = TradeID(raw)
        var loading = state
        loading.bestTrade = .loading
        state = loading

        if let cached = detailCache.trade(id: tradeID) {
            applyBestTrade(.available(cached))
            return
        }

        if let userID = await session.currentUserID {
            let owner = ProfileID(userID.rawValue)
            if let list = SessionOwnerTradesStore.shared.cached(for: owner),
               let hit = list.first(where: { $0.id == tradeID }) {
                detailCache.seed(hit)
                applyBestTrade(.available(hit))
                return
            }
        }

        do {
            let trade = try await trades.trade(id: tradeID)
            detailCache.seed(trade)
            applyBestTrade(.available(trade))
        } catch {
            applyBestTrade(.unavailable)
        }
    }

    private func applyBestTrade(_ value: ReportDetailState.BestTradeReference) {
        var next = state
        next.bestTrade = value
        state = next
    }
}
