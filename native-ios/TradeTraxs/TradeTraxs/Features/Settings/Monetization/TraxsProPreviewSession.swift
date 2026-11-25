import Foundation
import Observation

extension Notification.Name {
    /// Fired when a TraxsPro preview that routes journal reads through bundled sample data ends.
    /// The live Home ``DashboardViewModel`` should restore owner scope and chart hydration.
    static let traxsProCanonicalJournalPreviewDidEnd = Notification.Name(
        "traxspro.canonicalJournalPreview.didEnd"
    )
}

/// Cross-actor preview flag, readable from repositories without hopping to the main actor.
nonisolated enum TraxsProPreviewRuntimeFlag {
    nonisolated(unsafe) static var isReportsPreviewActive = false
    nonisolated(unsafe) static var isDashboardPreviewActive = false
    nonisolated(unsafe) static var isExpenseTrackerPreviewActive = false
    nonisolated(unsafe) static var isTradingRulesPreviewActive = false
    nonisolated(unsafe) static var isBacktestLabPreviewActive = false

    static var usesCanonicalJournalSampleData: Bool {
        isReportsPreviewActive || isDashboardPreviewActive || isTradingRulesPreviewActive
    }
}

/// Signed-in TraxsPro interactive preview, independent of Explore / ``AppLaunchController``.
@Observable
@MainActor
final class TraxsProPreviewSession {
    static let shared = TraxsProPreviewSession()

    private(set) var isReportsPreviewActive = false
    private(set) var isDashboardPreviewActive = false
    private(set) var isExpenseTrackerPreviewActive = false
    private(set) var isTradingRulesPreviewActive = false
    private(set) var isBacktestLabPreviewActive = false
    private(set) var activeFeature: TraxsProPreviewFeature?
    private var seededTradeIDs: [TradeID] = []
    private var previewSeededSessionCheckIns = false
    private var tradingRulesPreviewViewerID: ProfileID?

    private init() {}

    var isAnyPreviewActive: Bool {
        isReportsPreviewActive
            || isDashboardPreviewActive
            || isExpenseTrackerPreviewActive
            || isTradingRulesPreviewActive
            || isBacktestLabPreviewActive
    }

  /// Seeds demo trades into the detail cache for report / dashboard drill-down. Does not touch ``SessionOwnerTradesStore``.
    func beginReportsPreview(detailCache: DetailPresentationCache, viewer: ProfileID? = nil) {
        guard !isAnyPreviewActive else { return }
        isReportsPreviewActive = true
        activeFeature = .reports
        TraxsProPreviewRuntimeFlag.isReportsPreviewActive = true
        refreshRollingJournalForPreview()
        let trades = DemoCanonicalDataset.trades()
        seededTradeIDs = trades.map(\.id)
        if let viewer {
            DemoCanonicalDataset.seedDetailCache(detailCache, viewer: viewer)
            seedPreviewCheckIns(for: viewer, trades: trades)
        } else {
            DemoCanonicalDataset.seedDetailCache(detailCache)
        }
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
        TradingRulesAnalyticsPreviewSupport.seedJournalAndPreferences(
            profileID: viewer,
            detailCache: detailCache,
            seedDetailCacheTrades: false
        )
    }

    /// Expense tracker preview uses in-memory sample rows only, no journal or Supabase seeds.
    func beginExpenseTrackerPreview() {
        guard !isAnyPreviewActive else { return }
        isExpenseTrackerPreviewActive = true
        activeFeature = .expenseTracker
        TraxsProPreviewRuntimeFlag.isExpenseTrackerPreviewActive = true
    }

    /// Trading Rules Analytics preview, canonical trades, accounts, and sample rule preferences.
    /// Backtest Lab preview uses in-memory backtest trades only (no Supabase or live journal mixing).
    func beginBacktestLabPreview(detailCache: DetailPresentationCache, viewer: ProfileID) {
        guard !isAnyPreviewActive else { return }
        isBacktestLabPreviewActive = true
        activeFeature = .backtestLab
        TraxsProPreviewRuntimeFlag.isBacktestLabPreviewActive = true
        let trades = BacktestLabPreviewSampleData.trades(owner: viewer)
        seededTradeIDs = trades.map(\.id)
        BacktestLabPreviewSampleData.seedDetailCache(detailCache, owner: viewer)
    }

    func endBacktestLabPreview(detailCache: DetailPresentationCache) {
        guard isBacktestLabPreviewActive else { return }
        tearDownBacktestLabPreview(detailCache: detailCache)
    }

    func beginTradingRulesPreview(detailCache: DetailPresentationCache, viewer: ProfileID) {
        guard !isAnyPreviewActive else { return }
        isTradingRulesPreviewActive = true
        activeFeature = .tradingRules
        TraxsProPreviewRuntimeFlag.isTradingRulesPreviewActive = true
        tradingRulesPreviewViewerID = viewer
        refreshRollingJournalForPreview()
        let trades = DemoCanonicalDataset.trades()
        seededTradeIDs = trades.map(\.id)
        DemoCanonicalDataset.seedDetailCache(detailCache, viewer: viewer)
        seedPreviewCheckIns(for: viewer, trades: trades)
        TradingRulesAnalyticsPreviewSupport.seedJournalAndPreferences(
            profileID: viewer,
            detailCache: detailCache,
            seedDetailCacheTrades: false
        )
    }

    func endTradingRulesPreview(detailCache: DetailPresentationCache) {
        guard isTradingRulesPreviewActive else { return }
        tearDownTradingRulesPreview(detailCache: detailCache)
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
        if isBacktestLabPreviewActive {
            tearDownBacktestLabPreview(detailCache: detailCache)
            return
        }
        let canonicalJournalPreviewWasActive = TraxsProPreviewRuntimeFlag.usesCanonicalJournalSampleData
        isReportsPreviewActive = false
        isDashboardPreviewActive = false
        isExpenseTrackerPreviewActive = false
        isTradingRulesPreviewActive = false
        TraxsProPreviewRuntimeFlag.isReportsPreviewActive = false
        TraxsProPreviewRuntimeFlag.isDashboardPreviewActive = false
        TraxsProPreviewRuntimeFlag.isExpenseTrackerPreviewActive = false
        TraxsProPreviewRuntimeFlag.isTradingRulesPreviewActive = false
        activeFeature = nil
        tradingRulesPreviewViewerID = nil
        for id in seededTradeIDs {
            detailCache.removeTrade(id: id)
        }
        seededTradeIDs = []
        clearPreviewSessionCheckInsIfNeeded()
        if canonicalJournalPreviewWasActive {
            notifyCanonicalJournalPreviewDidEnd()
        }
    }

    private func notifyCanonicalJournalPreviewDidEnd() {
        NotificationCenter.default.post(name: .traxsProCanonicalJournalPreviewDidEnd, object: nil)
    }

    private func tearDownBacktestLabPreview(detailCache: DetailPresentationCache) {
        isBacktestLabPreviewActive = false
        TraxsProPreviewRuntimeFlag.isBacktestLabPreviewActive = false
        if activeFeature == .backtestLab {
            activeFeature = nil
        }
        for id in seededTradeIDs {
            detailCache.removeTrade(id: id)
        }
        seededTradeIDs = []
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

    private func tearDownTradingRulesPreview(detailCache: DetailPresentationCache) {
        let canonicalJournalPreviewWasActive = TraxsProPreviewRuntimeFlag.usesCanonicalJournalSampleData
        isTradingRulesPreviewActive = false
        TraxsProPreviewRuntimeFlag.isTradingRulesPreviewActive = false
        if activeFeature == .tradingRules {
            activeFeature = nil
        }
        if let viewer = tradingRulesPreviewViewerID {
            SessionOwnerTradesStore.shared.invalidate(profileID: viewer)
            TradingRulesCompliancePreferencesCache.invalidate(profileID: viewer)
            TradingRulesComplianceSessionStore.shared.reset()
        }
        tradingRulesPreviewViewerID = nil
        for id in seededTradeIDs {
            detailCache.removeTrade(id: id)
        }
        seededTradeIDs = []
        if canonicalJournalPreviewWasActive {
            notifyCanonicalJournalPreviewDidEnd()
        }
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

    static var isBacktestLabPreviewActive: Bool {
        TraxsProPreviewSession.shared.isBacktestLabPreviewActive
    }

    static func allowsJournalTradeNavigation(tradeID: TradeID) -> Bool {
        guard isAnyPreviewActive else { return true }
        if isBacktestLabPreviewActive {
            return BacktestLabPreviewSampleData.isPreviewTrade(id: tradeID)
        }
        return JournalSampleDataPolicy.isCanonicalTrade(id: tradeID)
    }
}