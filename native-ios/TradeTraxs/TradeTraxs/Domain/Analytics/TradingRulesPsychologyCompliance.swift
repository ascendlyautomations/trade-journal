import Foundation

/// Psychology discipline rules, consecutive-loss pause & wait-after-loss (trade-level checks).
nonisolated enum TradingRulesPsychologyCompliance {
    static func evaluate(
        contextTrades: [Trade],
        scopedTradeIDs: Set<String>,
        context: PreferenceRuleContext?,
        state: inout TradingRulesComplianceAnalytics.BuildState
    ) {
        guard !contextTrades.isEmpty, !scopedTradeIDs.isEmpty else { return }

        let ordered = contextTrades.sorted { lhs, rhs in
            if lhs.entryAt != rhs.entryAt { return lhs.entryAt < rhs.entryAt }
            return lhs.id.rawValue < rhs.id.rawValue
        }

        var consecutivePricedLossesByAccount: [AccountBucket: Int] = [:]
        var recordedKeys: Set<String> = []

        for trade in ordered {
            let bucket = AccountBucket(trade.accountID)
            var consecutivePricedLosses = consecutivePricedLossesByAccount[bucket] ?? 0

            let input = PreferenceComplianceEngine.input(from: trade)
            let rules = PreferenceComplianceEngine.rules(in: context, at: input.at, accountID: input.accountID)
            let inScope = scopedTradeIDs.contains(trade.id.rawValue)

            if inScope, let pause = rules.consecutiveLossPause, pause >= 1 {
                evaluateConsecutiveLossPause(
                    trade: trade,
                    input: input,
                    pause: pause,
                    streakAtEntry: consecutivePricedLosses,
                    recordedKeys: &recordedKeys,
                    state: &state
                )
            }

            if inScope, let waitMinutes = rules.waitAfterLossMinutes, waitMinutes > 0 {
                evaluateWaitAfterLoss(
                    trade: trade,
                    input: input,
                    waitMinutes: waitMinutes,
                    ordered: ordered,
                    recordedKeys: &recordedKeys,
                    state: &state
                )
            }

            applyStreak(trade: trade, consecutivePricedLosses: &consecutivePricedLosses)
            consecutivePricedLossesByAccount[bucket] = consecutivePricedLosses
        }
    }

    private struct AccountBucket: Hashable {
        var raw: String?
        init(_ accountID: TradingAccountID?) {
            raw = accountID?.rawValue
        }
    }

    private static func recordOnce(
        rule: TradingRulesComplianceAnalytics.RuleID,
        input: PreferenceComplianceEngine.Input,
        outcome: TradingRulesComplianceAnalytics.Outcome,
        detail: String,
        recordedKeys: inout Set<String>,
        state: inout TradingRulesComplianceAnalytics.BuildState
    ) {
        guard let tradeID = input.tradeID else { return }
        let key = "\(rule.rawValue)|\(tradeID)"
        guard !recordedKeys.contains(key) else { return }
        recordedKeys.insert(key)
        state.recordTrade(
            rule: rule,
            input: input,
            outcome: outcome,
            level: .trade,
            scope: nil,
            detail: detail
        )
    }

    private static func evaluateConsecutiveLossPause(
        trade: Trade,
        input: PreferenceComplianceEngine.Input,
        pause: Int,
        streakAtEntry: Int,
        recordedKeys: inout Set<String>,
        state: inout TradingRulesComplianceAnalytics.BuildState
    ) {
        let violated = streakAtEntry >= pause
        let detail: String
        if violated {
            detail =
                "Trade entered with \(streakAtEntry) consecutive priced losses before entry on this account (pause threshold \(pause)). Unpriced and breakeven trades do not extend the streak."
        } else {
            detail =
                "Trade entered with \(streakAtEntry) consecutive priced losses before entry on this account (under pause threshold of \(pause))."
        }
        recordOnce(
            rule: .consecutiveLossPause,
            input: input,
            outcome: violated ? .violated : .followed,
            detail: detail,
            recordedKeys: &recordedKeys,
            state: &state
        )
    }

    private static func previousLosingPricedTradeSameAccount(before trade: Trade, in ordered: [Trade]) -> Trade? {
        for candidate in ordered.reversed() {
            if candidate.id == trade.id { continue }
            guard candidate.entryAt < trade.entryAt else { continue }
            guard accountsMatch(candidate, trade) else { continue }
            guard let pnl = pricedPnL(for: candidate), pnl < 0 else { continue }
            return candidate
        }
        return nil
    }

    private static func accountsMatch(_ lhs: Trade, _ rhs: Trade) -> Bool {
        lhs.accountID == rhs.accountID
    }

    private static func pricedPnL(for trade: Trade) -> Double? {
        guard let amount = trade.realizedPnL?.amount else { return nil }
        return NSDecimalNumber(decimal: amount).doubleValue
    }

    private static func evaluateWaitAfterLoss(
        trade: Trade,
        input: PreferenceComplianceEngine.Input,
        waitMinutes: Int,
        ordered: [Trade],
        recordedKeys: inout Set<String>,
        state: inout TradingRulesComplianceAnalytics.BuildState
    ) {
        guard let previousLoss = previousLosingPricedTradeSameAccount(before: trade, in: ordered) else {
            recordOnce(
                rule: .waitAfterLoss,
                input: input,
                outcome: .notApplicable,
                detail: "No prior priced losing trade on this account before entry, wait rule does not apply.",
                recordedKeys: &recordedKeys,
                state: &state
            )
            return
        }

        guard let anchorExit = previousLoss.exitAt else {
            recordOnce(
                rule: .waitAfterLoss,
                input: input,
                outcome: .unevaluated,
                detail: "Prior losing trade is missing an exit time, cannot measure wait from loss exit.",
                recordedKeys: &recordedKeys,
                state: &state
            )
            return
        }

        let entry = trade.entryAt
        if entry <= anchorExit {
            recordOnce(
                rule: .waitAfterLoss,
                input: input,
                outcome: .unevaluated,
                detail: "Entry overlaps or precedes the prior loss exit, wait time is ambiguous.",
                recordedKeys: &recordedKeys,
                state: &state
            )
            return
        }

        let minutes = entry.timeIntervalSince(anchorExit) / 60
        guard minutes >= 0 else {
            recordOnce(
                rule: .waitAfterLoss,
                input: input,
                outcome: .unevaluated,
                detail: "Could not compute a non-negative wait interval from loss exit to entry.",
                recordedKeys: &recordedKeys,
                state: &state
            )
            return
        }

        let violated = minutes < Double(waitMinutes)
        let detail: String
        if violated {
            detail = String(
                format: "Entered %.0f min after the prior priced loss exit on this account (required wait %d min).",
                minutes,
                waitMinutes
            )
        } else {
            detail = String(
                format: "Waited %.0f min after the prior priced loss exit on this account (required %d min).",
                minutes,
                waitMinutes
            )
        }
        recordOnce(
            rule: .waitAfterLoss,
            input: input,
            outcome: violated ? .violated : .followed,
            detail: detail,
            recordedKeys: &recordedKeys,
            state: &state
        )
    }

  /// Priced wins reset the streak; priced losses extend it. Breakeven and missing P&L leave streak unchanged.
    private static func applyStreak(trade: Trade, consecutivePricedLosses: inout Int) {
        guard let pnl = pricedPnL(for: trade) else { return }
        if pnl > 0 {
            consecutivePricedLosses = 0
        } else if pnl < 0 {
            consecutivePricedLosses += 1
        }
    }
}
