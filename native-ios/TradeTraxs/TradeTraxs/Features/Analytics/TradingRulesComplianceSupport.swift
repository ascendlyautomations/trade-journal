import Foundation

nonisolated enum TradingRulesComplianceSupport {
    static func hasConfiguredRules(context: PreferenceRuleContext?) -> Bool {
        guard let context else { return false }
        if context.global == nil, context.overrides.isEmpty, context.revisions.isEmpty {
            return false
        }
        let rules = PreferenceComplianceEngine.configuredRulesNow(in: context)
        return rulesHasActiveChecksForEngine(rules)
    }

    static func rulesHasActiveChecksForEngine(_ rules: ResolvedTradingPreferences) -> Bool {
        rules.hasActiveRuleChecks
    }

    static func unevaluatedGuidance(for score: TradingRulesComplianceAnalytics.Score) -> String {
        guard score.unevaluated > 0 else { return score.explanation }
        return """
        \(score.unevaluated) checks could not be evaluated, missing session, instrument, planned R:R, contracts, dollar risk, max R reached, or psychology timing data. Not-applicable psychology checks are omitted from adherence. Unevaluated checks are never counted as compliant.

        \(score.explanation)
        """
    }

}
