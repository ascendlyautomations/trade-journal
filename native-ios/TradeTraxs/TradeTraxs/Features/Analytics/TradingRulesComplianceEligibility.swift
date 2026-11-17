import Foundation

/// Explains why compliance may show zero evaluations without changing engine semantics.
nonisolated enum TradingRulesComplianceEligibility {
    struct Summary: Sendable, Equatable {
        var scopedTradeCount: Int
        var tradesWithActiveRulesAtEntry: Int
        var tradesBeforeFirstSavedRule: Int
        var firstGlobalRuleEffectiveAt: Date?
        var usesRevisionHistory: Bool
        var applyRulesToPastTrades: Bool
        var retrospectivelyScoredTrades: Int
        var skipReasons: [String: Int]

        var userMessage: String? {
            guard scopedTradeCount > 0 else { return nil }
            if !usesRevisionHistory {
                return "No saved rule history is on file yet. Save Trading Rules in Settings to record your configuration; until then, compliance can’t score trades in this scope."
            }
            if applyRulesToPastTrades, retrospectivelyScoredTrades > 0, let first = firstGlobalRuleEffectiveAt {
                let formatted = TradingRulesComplianceEligibility.displayDate(first)
                if retrospectivelyScoredTrades == scopedTradeCount {
                    return "\(scopedTradeCount) trades are before your first saved rules (\(formatted)) and are scored using your current rules."
                }
                return "\(retrospectivelyScoredTrades) trades before your first saved rules (\(formatted)) are scored using your current rules."
            }
            if tradesWithActiveRulesAtEntry == 0, let first = firstGlobalRuleEffectiveAt {
                let formatted = TradingRulesComplianceEligibility.displayDate(first)
                if tradesBeforeFirstSavedRule == scopedTradeCount {
                    return "Your current rules were first saved on \(formatted). All \(scopedTradeCount) trades in this scope are from before that date, so none are scored. Turn on “Apply Rules to Past Trades” in Settings → Trading Rules to include them."
                }
                return "\(tradesBeforeFirstSavedRule) of \(scopedTradeCount) trades are before your first saved rules (\(formatted)) and are excluded from scoring."
            }
            if tradesWithActiveRulesAtEntry > 0, let top = skipReasons.max(by: { $0.value < $1.value }), top.value > 0 {
                return "\(tradesWithActiveRulesAtEntry) trades could be checked, but many entries are missing data (\(top.key)). Fill session, symbol, R:R, contracts, and dollar risk on trades to evaluate more rules."
            }
            return nil
        }
    }

    static func analyze(
        trades: [Trade],
        context: PreferenceRuleContext?
    ) -> Summary {
        let inputs = trades.map(PreferenceComplianceEngine.input(from:)).sorted { $0.at < $1.at }
        let rulesCache = TradingRulesResolvedRulesCache(context: context, inputs: inputs)
        return analyze(inputs: inputs, context: context, rulesCache: rulesCache)
    }

    static func analyze(
        inputs: [PreferenceComplianceEngine.Input],
        context: PreferenceRuleContext?,
        rulesCache: TradingRulesResolvedRulesCache
    ) -> Summary {
        let usesHistory = !(context?.revisions.isEmpty ?? true)

        let firstGlobalRuleEffectiveAt = PreferenceComplianceEngine.firstGlobalRuleEffectiveAt(in: context)

        let applyPast = PreferenceComplianceEngine.applyRulesToPastTradesEnabled(in: context)

        var tradesWithActiveRules = 0
        var tradesBeforeFirstRule = 0
        var retrospectivelyScored = 0
        var skipReasons: [String: Int] = [:]

        for input in inputs {
            let rules = rulesCache.rules(for: input)
            guard TradingRulesComplianceSupport.rulesHasActiveChecksForEngine(rules) else {
                if let first = firstGlobalRuleEffectiveAt, input.at < first {
                    tradesBeforeFirstRule += 1
                    skipReasons["before_first_saved_rule", default: 0] += 1
                } else if rules.source == .unset {
                    skipReasons["no_rules_at_trade_time", default: 0] += 1
                } else {
                    skipReasons["rules_inactive_at_trade_time", default: 0] += 1
                }
                continue
            }
            tradesWithActiveRules += 1
            if applyPast,
               PreferenceComplianceEngine.usesRetrospectiveRuleApplication(
                   in: context,
                   at: input.at,
                   accountID: input.accountID
               )
            {
                retrospectivelyScored += 1
            }
            accumulateMissingFieldSkips(rules: rules, input: input, into: &skipReasons)
        }

        return Summary(
            scopedTradeCount: inputs.count,
            tradesWithActiveRulesAtEntry: tradesWithActiveRules,
            tradesBeforeFirstSavedRule: tradesBeforeFirstRule,
            firstGlobalRuleEffectiveAt: firstGlobalRuleEffectiveAt,
            usesRevisionHistory: usesHistory,
            applyRulesToPastTrades: applyPast,
            retrospectivelyScoredTrades: retrospectivelyScored,
            skipReasons: skipReasons
        )
    }

    private static func accumulateMissingFieldSkips(
        rules: ResolvedTradingPreferences,
        input: PreferenceComplianceEngine.Input,
        into skipReasons: inout [String: Int]
    ) {
        if !rules.preferredSessions.isEmpty, input.session == nil {
            skipReasons["missing_session", default: 0] += 1
        }
        if !rules.primaryInstruments.isEmpty, input.symbol == nil {
            skipReasons["missing_symbol", default: 0] += 1
        }
        if rules.plannedHours != nil, input.easternMinute < 0 {
            skipReasons["missing_entry_time", default: 0] += 1
        }
        if rules.minAcceptableRr != nil, input.plannedRr == nil {
            skipReasons["missing_planned_rr", default: 0] += 1
        }
        if rules.maxContractsPerTrade != nil, input.contracts == nil {
            skipReasons["missing_contracts", default: 0] += 1
        }
        if rules.maxRiskPerTrade != nil, input.dollarRisk == nil {
            skipReasons["missing_dollar_risk", default: 0] += 1
        }
        if rules.targetRr != nil, input.maxRr == nil {
            skipReasons["missing_max_rr", default: 0] += 1
        }
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
