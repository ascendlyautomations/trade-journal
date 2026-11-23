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
    private let weekRef: TradingReportWeekRef?
    private let customRangeRef: TradingReportCustomRangeRef?
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
        if let weekRef = TradingReportWeekRef.parse(reportID: reportID) {
            self.weekRef = weekRef
            self.monthRef = nil
            self.customRangeRef = nil
            self.periodKey = .weeklyThis
        } else if let monthRef = TradingReportMonthRef.parse(reportID: reportID) {
            self.monthRef = monthRef
            self.weekRef = nil
            self.customRangeRef = nil
            self.periodKey = .monthlyThis
        } else if let customRef = TradingReportCustomRangeRef.parse(reportID: reportID) {
            self.customRangeRef = customRef
            self.monthRef = nil
            self.weekRef = nil
            self.periodKey = .monthlyThis
        } else {
            self.monthRef = nil
            self.weekRef = nil
            self.customRangeRef = nil
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
        self.weekRef = nil
        self.customRangeRef = nil
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

    var isWeekly: Bool {
        weekRef != nil || periodKey.kind == .weekly || state.report?.kind == .weekly
    }
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
        guard TraxsProPreviewSupport.allowsJournalTradeNavigation(tradeID: trade.id) else { return }
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
            if let weekRef {
                result = try await ReportDetailBootstrap.loadWeek(
                    ReportDetailBootstrap.WeekContext(
                        mondayKey: weekRef.mondayKey,
                        filters: TradingReportSessionStore.shared.filters,
                        tradingReports: tradingReports,
                        forceNetwork: forceNetwork
                    )
                )
            } else if let monthRef {
                result = try await ReportDetailBootstrap.loadMonth(
                    ReportDetailBootstrap.MonthContext(
                        monthRef: monthRef,
                        filters: TradingReportSessionStore.shared.filters,
                        tradingReports: tradingReports,
                        forceNetwork: forceNetwork
                    )
                )
            } else if let customRangeRef {
                result = try await ReportDetailBootstrap.loadCustom(
                    ReportDetailBootstrap.CustomContext(
                        ref: customRangeRef,
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
            if TraxsProPreviewSupport.isReportsPreviewActive,
               !JournalSampleDataPolicy.isCanonicalTrade(id: cached.id) {
                applyBestTrade(.unavailable)
                return
            }
            applyBestTrade(.available(cached))
            return
        }

        if TraxsProPreviewSupport.isReportsPreviewActive {
            if let sample = DemoCanonicalDataset.trades().first(where: { $0.id == tradeID }) {
                detailCache.seed(sample)
                applyBestTrade(.available(sample))
            } else {
                applyBestTrade(.unavailable)
            }
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
