import Foundation
import Observation

extension Notification.Name {
    /// Fired when a TraxsPro preview that routed journal reads through bundled sample data ends.
    /// The live Home ``DashboardViewModel`` should restore owner scope and chart hydration.
    static let traxsProCanonicalJournalPreviewDidEnd = Notification.Name(
        "traxspro.canonicalJournalPreview.didEnd"
    )
}

/// Cross-actor preview flag, readable for UI / monetization policy only — not for repository routing.
nonisolated enum TraxsProPreviewRuntimeFlag {
    nonisolated(unsafe) static var isReportsPreviewActive = false
    nonisolated(unsafe) static var isDashboardPreviewActive = false
    nonisolated(unsafe) static var isExpenseTrackerPreviewActive = false
    nonisolated(unsafe) static var isTradingRulesPreviewActive = false
    nonisolated(unsafe) static var isBacktestLabPreviewActive = false

    @available(*, deprecated, message: "Use TraxsProPreviewDataEnvironment instead of global journal routing.")
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
    private(set) var activePreviewEnvironment: TraxsProPreviewDataEnvironment?

    private var previewGeneration: UInt64 = 0
    private var previewSeededSessionCheckIns = false

    private init() {}

    var isAnyPreviewActive: Bool {
        isReportsPreviewActive
            || isDashboardPreviewActive
            || isExpenseTrackerPreviewActive
            || isTradingRulesPreviewActive
            || isBacktestLabPreviewActive
    }

    func bumpPreviewGeneration() -> UInt64 {
        previewGeneration &+= 1
        return previewGeneration
    }

    func previewData(for feature: TraxsProPreviewFeature) -> DataEnvironment? {
        guard activePreviewEnvironment?.feature == feature else { return nil }
        return activePreviewEnvironment?.data
    }

    func beginReportsPreview(production: DataEnvironment, viewer: ProfileID) {
        guard !isAnyPreviewActive else { return }
        isReportsPreviewActive = true
        activeFeature = .reports
        TraxsProPreviewRuntimeFlag.isReportsPreviewActive = true
        refreshRollingJournalForPreview()
        finishActivatingPreview(
            TraxsProPreviewDataEnvironment.make(
                from: production,
                viewer: viewer,
                feature: .reports
            )
        )
    }

    func beginDashboardPreview(production: DataEnvironment, viewer: ProfileID) {
        guard !isAnyPreviewActive else {
            RulesPreviewDebugLog.log("beginDashboardPreview skipped: another preview is active")
            return
        }
        RulesPreviewDebugLog.log("beginDashboardPreview viewer=\(viewer.rawValue)")
        isDashboardPreviewActive = true
        activeFeature = .dashboard
        TraxsProPreviewRuntimeFlag.isDashboardPreviewActive = true
        refreshRollingJournalForPreview()
        finishActivatingPreview(
            TraxsProPreviewDataEnvironment.make(
                from: production,
                viewer: viewer,
                feature: .dashboard
            )
        )
    }

    /// Expense tracker preview uses in-memory sample rows only, no journal or Supabase seeds.
    func beginExpenseTrackerPreview(production: DataEnvironment, viewer: ProfileID) {
        guard !isAnyPreviewActive else { return }
        isExpenseTrackerPreviewActive = true
        activeFeature = .expenseTracker
        TraxsProPreviewRuntimeFlag.isExpenseTrackerPreviewActive = true
        finishActivatingPreview(
            TraxsProPreviewDataEnvironment.make(
                from: production,
                viewer: viewer,
                feature: .expenseTracker
            )
        )
    }

    func beginBacktestLabPreview(production: DataEnvironment, viewer: ProfileID) {
        guard !isAnyPreviewActive else { return }
        isBacktestLabPreviewActive = true
        activeFeature = .backtestLab
        TraxsProPreviewRuntimeFlag.isBacktestLabPreviewActive = true
        let env = TraxsProPreviewDataEnvironment.make(
            from: production,
            viewer: viewer,
            feature: .backtestLab
        )
        env.seedBacktestDetailCache()
        finishActivatingPreview(env)
    }

    func endBacktestLabPreview() {
        guard isBacktestLabPreviewActive else { return }
        tearDownPreviewFlags()
    }

    func beginTradingRulesPreview(production: DataEnvironment, viewer: ProfileID) {
        guard !isAnyPreviewActive else { return }
        isTradingRulesPreviewActive = true
        activeFeature = .tradingRules
        TraxsProPreviewRuntimeFlag.isTradingRulesPreviewActive = true
        refreshRollingJournalForPreview()
        finishActivatingPreview(
            TraxsProPreviewDataEnvironment.make(
                from: production,
                viewer: viewer,
                feature: .tradingRules
            )
        )
    }

    func endTradingRulesPreview() {
        guard isTradingRulesPreviewActive else { return }
        tearDownPreviewFlags()
    }

    func endReportsPreview() {
        guard isReportsPreviewActive else { return }
        tearDownPreviewFlags()
    }

    func endDashboardPreview() {
        guard isDashboardPreviewActive else { return }
        tearDownPreviewFlags()
    }

    func endExpenseTrackerPreview() {
        guard isExpenseTrackerPreviewActive else { return }
        tearDownPreviewFlags()
    }

    func endActivePreview() {
        guard isAnyPreviewActive else { return }
        tearDownPreviewFlags()
    }

    private func tearDownPreviewFlags() {
        isReportsPreviewActive = false
        isDashboardPreviewActive = false
        isExpenseTrackerPreviewActive = false
        isTradingRulesPreviewActive = false
        isBacktestLabPreviewActive = false
        TraxsProPreviewRuntimeFlag.isReportsPreviewActive = false
        TraxsProPreviewRuntimeFlag.isDashboardPreviewActive = false
        TraxsProPreviewRuntimeFlag.isExpenseTrackerPreviewActive = false
        TraxsProPreviewRuntimeFlag.isTradingRulesPreviewActive = false
        TraxsProPreviewRuntimeFlag.isBacktestLabPreviewActive = false
        activeFeature = nil
        activePreviewEnvironment?.invalidateGeneration()
        activePreviewEnvironment = nil
        previewSeededSessionCheckIns = false
        RulesPreviewDebugLog.log("tearDownPreviewFlags clearing preview presentation stores")
        TradingRulesCompliancePresentationStores.clearPreview()
        TradingScorecardPresentationStores.clearPreview()
    }

    private func finishActivatingPreview(_ environment: TraxsProPreviewDataEnvironment) {
        activePreviewEnvironment = environment
        TradingRulesCompliancePresentationStores.bindPreview(environment.rulesPresentationStore)
        TradingScorecardPresentationStores.bindPreview(environment.scorecardPresentationStore)
        TradingRulesAnalyticsPreviewSupport.seedActivePreviewEnvironmentRulesPresentation()
        RulesPreviewDebugLog.log(
            "finishActivatingPreview \(RulesPreviewDebugLog.describe(environment))"
        )
    }

    private func refreshRollingJournalForPreview() {
        DemoRollingJournal.shared.invalidateCache()
        _ = DemoRollingJournal.shared.trades(forceRebuild: true)
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

    /// Bundled journal inputs for the isolated Reports preview (never session owner stores).
    struct ReportsJournalBundle: Sendable {
        let trades: [Trade]
        let accounts: [TradingAccount]
        let checkIns: [TraderDailyCheckIn]
    }

    static func reportsJournalBundle(for profileID: ProfileID) -> ReportsJournalBundle? {
        guard isReportsPreviewActive,
              let preview = TraxsProPreviewSession.shared.activePreviewEnvironment,
              preview.viewer == profileID
        else { return nil }
        return ReportsJournalBundle(
            trades: preview.trades,
            accounts: preview.accounts,
            checkIns: preview.checkIns
        )
    }

    static func allowsJournalTradeNavigation(tradeID: TradeID) -> Bool {
        guard isAnyPreviewActive else { return true }
        if isBacktestLabPreviewActive {
            return BacktestLabPreviewSampleData.isPreviewTrade(id: tradeID)
        }
        return JournalSampleDataPolicy.isCanonicalTrade(id: tradeID)
    }
}