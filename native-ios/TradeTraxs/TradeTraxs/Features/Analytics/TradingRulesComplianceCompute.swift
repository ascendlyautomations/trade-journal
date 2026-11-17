import Foundation

/// Background-safe compliance bundle (analytics math unchanged; runs off the main actor).
nonisolated enum TradingRulesComplianceCompute {
    struct Timings: Sendable, Equatable {
        var rulesCacheMs: Double = 0
        var priorDisciplineMs: Double = 0
        var analyticsMs: Double = 0
        var eligibilityMs: Double = 0
        var personalInsightsMs: Double = 0
        var totalMs: Double = 0
    }

    struct DisciplineContext: Sendable {
        var psychologyContextTrades: [Trade] = []
        var priorTrades: [Trade] = []
        var complianceGoalPercent: Double = TradingRulesDisciplineProgress.defaultGoalPercent
    }

    struct ScopedPayload: Sendable {
        var result: TradingRulesComplianceAnalytics.Result
        var eligibility: TradingRulesComplianceEligibility.Summary
        var personalInsights: [DashboardInsightItem]
        var timings: Timings
    }

    static func computeScoped(
        trades: [Trade],
        context: PreferenceRuleContext?,
        dashboardInsights: DashboardInsightsPresentation?,
        preferDashboardInsightsCache: Bool,
        discipline: DisciplineContext = DisciplineContext()
    ) async -> ScopedPayload {
        await Task.detached(priority: .userInitiated) {
            computeScopedSync(
                trades: trades,
                context: context,
                dashboardInsights: dashboardInsights,
                preferDashboardInsightsCache: preferDashboardInsightsCache,
                discipline: discipline
            )
        }.value
    }

    static func computeScopedSync(
        trades: [Trade],
        context: PreferenceRuleContext?,
        dashboardInsights: DashboardInsightsPresentation?,
        preferDashboardInsightsCache: Bool,
        discipline: DisciplineContext = DisciplineContext()
    ) -> ScopedPayload {
        let started = CFAbsoluteTimeGetCurrent()
        let inputs = TradingRulesComplianceAnalytics.complianceInputs(from: trades)

        let rulesStarted = CFAbsoluteTimeGetCurrent()
        let rulesCache = TradingRulesResolvedRulesCache(context: context, inputs: inputs)
        let rulesCacheMs = (CFAbsoluteTimeGetCurrent() - rulesStarted) * 1000

        let priorStarted = CFAbsoluteTimeGetCurrent()
        let priorDiscipline: TradingRulesDisciplineProgress.PriorMetrics?
        if discipline.priorTrades.isEmpty {
            priorDiscipline = nil
        } else {
            priorDiscipline = TradingRulesComplianceAnalytics.buildDisciplinePriorMetrics(
                trades: discipline.priorTrades,
                context: context,
                psychologyContextTrades: discipline.psychologyContextTrades
            )
        }
        let priorDisciplineMs = (CFAbsoluteTimeGetCurrent() - priorStarted) * 1000

        let analyticsStarted = CFAbsoluteTimeGetCurrent()
        let result = TradingRulesComplianceAnalytics.build(
            inputs: inputs,
            context: context,
            rulesCache: rulesCache,
            trades: trades,
            psychologyContextTrades: discipline.psychologyContextTrades,
            priorDisciplineMetrics: priorDiscipline,
            complianceGoalPercent: discipline.complianceGoalPercent
        )
        let analyticsMs = (CFAbsoluteTimeGetCurrent() - analyticsStarted) * 1000

        let eligibilityStarted = CFAbsoluteTimeGetCurrent()
        let eligibility = TradingRulesComplianceEligibility.analyze(
            inputs: inputs,
            context: context,
            rulesCache: rulesCache
        )
        let eligibilityMs = (CFAbsoluteTimeGetCurrent() - eligibilityStarted) * 1000

        let insightsStarted = CFAbsoluteTimeGetCurrent()
        let personalInsights = TradingRulesPersonalInsights.resolve(
            dashboardPresentation: dashboardInsights,
            preferDashboardCache: preferDashboardInsightsCache,
            trades: trades,
            preferences: context,
            compliance: result
        )
        let personalInsightsMs = (CFAbsoluteTimeGetCurrent() - insightsStarted) * 1000

        let totalMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
        return ScopedPayload(
            result: result,
            eligibility: eligibility,
            personalInsights: personalInsights,
            timings: Timings(
                rulesCacheMs: rulesCacheMs,
                priorDisciplineMs: priorDisciplineMs,
                analyticsMs: analyticsMs,
                eligibilityMs: eligibilityMs,
                personalInsightsMs: personalInsightsMs,
                totalMs: totalMs
            )
        )
    }
}
