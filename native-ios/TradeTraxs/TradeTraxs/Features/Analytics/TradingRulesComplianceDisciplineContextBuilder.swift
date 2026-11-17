import Foundation

/// Shared discipline + psychology history inputs for Dashboard and Analytics (parity).
nonisolated enum TradingRulesComplianceDisciplineContextBuilder {
    struct Prepared: Sendable {
        var discipline: TradingRulesComplianceCompute.DisciplineContext
        var psychologyContextTrades: [Trade]
        var priorPeriodTrades: [Trade]
        var historyComplete: Bool
        var ownerTradeCount: Int
        var requiresCompleteHistoryForPsychology: Bool
    }

    static func requiresCompleteHistoryForPsychology(context: PreferenceRuleContext?) -> Bool {
        guard let global = context?.global else {
            return configuredRulesNowRequirePsychology(context: context)
        }
        if let pause = global.consecutiveLossPause, pause >= 1 { return true }
        if let wait = global.waitAfterLossMinutes, wait > 0 { return true }
        return configuredRulesNowRequirePsychology(context: context)
    }

    private static func configuredRulesNowRequirePsychology(context: PreferenceRuleContext?) -> Bool {
        let rules = PreferenceComplianceEngine.configuredRulesNow(in: context)
        if let pause = rules.consecutiveLossPause, pause >= 1 { return true }
        if let wait = rules.waitAfterLossMinutes, wait > 0 { return true }
        return false
    }

    static func prepare(
        ownerTrades: [Trade],
        accounts: [TradingAccount],
        scopeFilter: DashboardClientScopeFilter,
        preferences: PreferenceRuleContext?,
        historyComplete: Bool
    ) -> Prepared {
        var accountScope = scopeFilter
        accountScope.dateRange = .all
        accountScope.customInterval = nil
        if !accounts.isEmpty {
            accountScope.linkedAccountModes = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        }

        let psychologyContext = PsychologyAnalyticsTradeScope.scopedTrades(
            ownerTrades: ownerTrades,
            accounts: accounts,
            scope: accountScope
        )

        let priorPeriodTrades = TradingRulesDisciplineProgress.priorTrades(
            ownerTrades: ownerTrades,
            accounts: accounts,
            scope: scopeFilter
        )

        let goal = preferences?.global?.personalComplianceTargetPercent
            ?? TradingRulesDisciplineProgress.defaultGoalPercent

        let discipline = TradingRulesComplianceCompute.DisciplineContext(
            psychologyContextTrades: psychologyContext,
            priorTrades: priorPeriodTrades,
            complianceGoalPercent: goal
        )

        return Prepared(
            discipline: discipline,
            psychologyContextTrades: psychologyContext,
            priorPeriodTrades: priorPeriodTrades,
            historyComplete: historyComplete,
            ownerTradeCount: ownerTrades.count,
            requiresCompleteHistoryForPsychology: requiresCompleteHistoryForPsychology(context: preferences)
        )
    }
}
