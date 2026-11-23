import Foundation
import Observation

/// Cross-actor preview flag — readable from repositories without hopping to the main actor.
nonisolated enum TraxsProPreviewRuntimeFlag {
    nonisolated(unsafe) static var isReportsPreviewActive = false
    nonisolated(unsafe) static var isDashboardPreviewActive = false
    nonisolated(unsafe) static var isExpenseTrackerPreviewActive = false

    static var usesCanonicalJournalSampleData: Bool {
        isReportsPreviewActive || isDashboardPreviewActive
    }
}

/// Signed-in TraxsPro interactive preview — independent of Explore / ``AppLaunchController``.
@Observable
@MainActor
final class TraxsProPreviewSession {
    static let shared = TraxsProPreviewSession()

    private(set) var isReportsPreviewActive = false
    private(set) var isDashboardPreviewActive = false
    private(set) var isExpenseTrackerPreviewActive = false
    private(set) var isTradingRulesPreviewActive = false
    private(set) var activeFeature: TraxsProPreviewFeature?
    private var seededTradeIDs: [TradeID] = []
    private var previewSeededSessionCheckIns = false

    private init() {}

    var isAnyPreviewActive: Bool {
        isReportsPreviewActive
            || isDashboardPreviewActive
            || isExpenseTrackerPreviewActive
            || isTradingRulesPreviewActive
    }

  /// Seeds demo trades into the detail cache for report / dashboard drill-down. Does not touch ``SessionOwnerTradesStore``.
    func beginReportsPreview(detailCache: DetailPresentationCache) {
        guard !isAnyPreviewActive else { return }
        isReportsPreviewActive = true
        activeFeature = .reports
        TraxsProPreviewRuntimeFlag.isReportsPreviewActive = true
        refreshRollingJournalForPreview()
        let trades = DemoCanonicalDataset.trades()
        seededTradeIDs = trades.map(\.id)
        DemoCanonicalDataset.seedDetailCache(detailCache)
    }

    func beginDashboardPreview(detailCache: DetailPresentationCache, viewer: ProfileID) {
        guard !isAnyPreviewActive else { return }
        isDashboardPreviewActive = true
        activeFeature = .dashboard
        TraxsProPreviewRuntimeFlag.isDashboardPreviewActive = true
        refreshRollingJournalForPreview()
        let trades = DemoCanonicalDataset.trades()
        seededTradeIDs = trades.map(\.id)
        DemoCanonicalDataset.seedDetailCache(detailCache, viewer: viewer)
        seedPreviewCheckIns(for: viewer, trades: trades)
    }

    /// Expense tracker preview uses in-memory sample rows only — no journal or Supabase seeds.
    func beginExpenseTrackerPreview() {
        guard !isAnyPreviewActive else { return }
        isExpenseTrackerPreviewActive = true
        activeFeature = .expenseTracker
        TraxsProPreviewRuntimeFlag.isExpenseTrackerPreviewActive = true
    }

    /// Trading Rules settings preview — sample preferences only (no persistence).
    func beginTradingRulesPreview() {
        guard !isAnyPreviewActive else { return }
        isTradingRulesPreviewActive = true
        activeFeature = .tradingRules
    }

    func endTradingRulesPreview() {
        guard isTradingRulesPreviewActive else { return }
        isTradingRulesPreviewActive = false
        if activeFeature == .tradingRules {
            activeFeature = nil
        }
    }

    /// Ends preview and removes only demo trade seeds from the detail cache.
    func endReportsPreview(detailCache: DetailPresentationCache) {
        guard isReportsPreviewActive else { return }
        tearDownPreview(detailCache: detailCache)
    }

    func endDashboardPreview(detailCache: DetailPresentationCache) {
        guard isDashboardPreviewActive else { return }
        tearDownPreview(detailCache: detailCache)
    }

    func endExpenseTrackerPreview() {
        guard isExpenseTrackerPreviewActive else { return }
        isExpenseTrackerPreviewActive = false
        TraxsProPreviewRuntimeFlag.isExpenseTrackerPreviewActive = false
        if activeFeature == .expenseTracker {
            activeFeature = nil
        }
    }

    func endActivePreview(detailCache: DetailPresentationCache) {
        guard isAnyPreviewActive else { return }
        tearDownPreview(detailCache: detailCache)
    }

    private func tearDownPreview(detailCache: DetailPresentationCache) {
        isReportsPreviewActive = false
        isDashboardPreviewActive = false
        isExpenseTrackerPreviewActive = false
        isTradingRulesPreviewActive = false
        TraxsProPreviewRuntimeFlag.isReportsPreviewActive = false
        TraxsProPreviewRuntimeFlag.isDashboardPreviewActive = false
        TraxsProPreviewRuntimeFlag.isExpenseTrackerPreviewActive = false
        activeFeature = nil
        for id in seededTradeIDs {
            detailCache.removeTrade(id: id)
        }
        seededTradeIDs = []
        clearPreviewSessionCheckInsIfNeeded()
    }

    private func refreshRollingJournalForPreview() {
        DemoRollingJournal.shared.invalidateCache()
        _ = DemoRollingJournal.shared.trades(forceRebuild: true)
    }

    private func seedPreviewCheckIns(for viewer: ProfileID, trades: [Trade]) {
        let checkIns = DemoCanonicalDataset.checkIns()
        guard let start = checkIns.map(\.checkInDate).min(),
              let end = checkIns.map(\.checkInDate).max()
        else { return }
        let eligible = trades.filter { $0.mode != .backtest }
        SessionDailyCheckInsStore.shared.seed(checkIns, for: viewer, range: (start, end))
        CheckInHistorySessionStore.shared.update(
            summaries: CheckInHistoryAggregator.buildSummaries(checkIns: checkIns, trades: eligible),
            checkIns: checkIns,
            trades: eligible
        )
        previewSeededSessionCheckIns = true
    }

    private func clearPreviewSessionCheckInsIfNeeded() {
        guard previewSeededSessionCheckIns else { return }
        SessionDailyCheckInsStore.shared.invalidate()
        CheckInHistorySessionStore.shared.invalidate()
        previewSeededSessionCheckIns = false
    }
}

/// Read-only + navigation guardrails for TraxsPro interactive previews.
@MainActor
enum TraxsProPreviewSupport {
    static var isAnyPreviewActive: Bool {
        TraxsProPreviewSession.shared.isAnyPreviewActive
    }

    static var isReportsPreviewActive: Bool {
        TraxsProPreviewSession.shared.isReportsPreviewActive
    }

    static var isDashboardPreviewActive: Bool {
        TraxsProPreviewSession.shared.isDashboardPreviewActive
    }

    static var isExpenseTrackerPreviewActive: Bool {
        TraxsProPreviewSession.shared.isExpenseTrackerPreviewActive
    }

    static var isTradingRulesPreviewActive: Bool {
        TraxsProPreviewSession.shared.isTradingRulesPreviewActive
    }

    static var canMutateJournal: Bool { !isAnyPreviewActive }

    static func allowsJournalTradeNavigation(tradeID: TradeID) -> Bool {
        guard isAnyPreviewActive else { return true }
        return JournalSampleDataPolicy.isCanonicalTrade(id: tradeID)
    }
}