import Foundation
import os

nonisolated enum TradingRulesComplianceDiagnostics {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "TradingRulesCompliance")

    struct Snapshot: Sendable {
        var scopedTradeCount: Int
        var ownerTradeCount: Int
        var configuredRuleFamilies: Int
        var evaluatedChecks: Int
        var violations: Int
        var followed: Int
        var unevaluated: Int
        var preferencesLoaded: Bool
        var historyComplete: Bool
    }

    static func log(_ snapshot: Snapshot) {
        log.info(
            "scopedTrades=\(snapshot.scopedTradeCount, privacy: .public) ownerTrades=\(snapshot.ownerTradeCount, privacy: .public) ruleFamilies=\(snapshot.configuredRuleFamilies, privacy: .public) evaluated=\(snapshot.evaluatedChecks, privacy: .public) followed=\(snapshot.followed, privacy: .public) violations=\(snapshot.violations, privacy: .public) unevaluated=\(snapshot.unevaluated, privacy: .public) prefs=\(snapshot.preferencesLoaded, privacy: .public) historyComplete=\(snapshot.historyComplete, privacy: .public)"
        )
    }

    static func logTimings(_ timings: TradingRulesComplianceCompute.Timings, source: String) {
        log.info(
            "perf source=\(source, privacy: .public) totalMs=\(timings.totalMs, privacy: .public) rulesCacheMs=\(timings.rulesCacheMs, privacy: .public) analyticsMs=\(timings.analyticsMs, privacy: .public) eligibilityMs=\(timings.eligibilityMs, privacy: .public) insightsMs=\(timings.personalInsightsMs, privacy: .public)"
        )
    }

    static func logEligibility(_ summary: TradingRulesComplianceEligibility.Summary) {
        let skipSummary = summary.skipReasons
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        log.info(
            "eligibility scoped=\(summary.scopedTradeCount, privacy: .public) withRules=\(summary.tradesWithActiveRulesAtEntry, privacy: .public) beforeFirstRule=\(summary.tradesBeforeFirstSavedRule, privacy: .public) revisionHistory=\(summary.usesRevisionHistory, privacy: .public) skips=[\(skipSummary, privacy: .public)]"
        )
    }

    static func configuredRuleFamilyCount(context: PreferenceRuleContext?) -> Int {
        guard let context else { return 0 }
        let rules = PreferenceComplianceEngine.configuredRulesNow(in: context)
        var count = 0
        if !rules.preferredSessions.isEmpty { count += 1 }
        if !rules.primaryInstruments.isEmpty { count += 1 }
        if rules.plannedHours != nil { count += 1 }
        if !rules.allowedTradingDays.isEmpty { count += 1 }
        if rules.minAcceptableRr != nil { count += 1 }
        if rules.maxContractsPerTrade != nil { count += 1 }
        if rules.maxRiskPerTrade != nil { count += 1 }
        if rules.targetRr != nil { count += 1 }
        if rules.maxTradesPerDay != nil { count += 1 }
        if rules.dailyLossLimit != nil { count += 1 }
        if rules.stopAfterDailyProfitTarget, rules.dailyProfitTarget != nil { count += 1 }
        if rules.maxWeeklyLoss != nil { count += 1 }
        return count
    }
}
