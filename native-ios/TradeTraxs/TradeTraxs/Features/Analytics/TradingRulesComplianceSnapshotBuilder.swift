import Foundation

@MainActor
enum TradingRulesComplianceSnapshotBuilder {
    struct Output: Sendable {
        var result: TradingRulesComplianceAnalytics.Result?
        var hasConfiguredRules: Bool
        var scopedTradeCount: Int
        var ownerTradeCount: Int
        var preferencesContext: PreferenceRuleContext?
        var preferencesError: String?
        var tradesError: String?
        var insufficientScope: Bool
        var historyComplete: Bool
        var eligibility: TradingRulesComplianceEligibility.Summary?
        var personalInsights: [DashboardInsightItem] = []
        /// When false, dashboard may show the snapshot as provisional while owner history finishes.
        var isAuthoritative: Bool = true
    }

    enum PreferenceLoadOutcome {
        case loaded(PreferenceRuleContext)
        case failed(String)
        case skipped
    }

    static func build(
        profileID: ProfileID,
        scope: PsychologyAnalyticsScopeResolver.Resolved,
        accounts: [TradingAccount],
        dependencies: TradingRulesComplianceLoadDependencies,
        injectedPreferences: PreferenceRuleContext? = nil,
        dashboardInsights: DashboardInsightsPresentation? = nil
    ) async -> Output {
        let previewChromeActive = TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome
        if previewChromeActive {
            RulesPreviewDebugLog.log(
                "SnapshotBuilder.build preview chrome active profileID=\(profileID.rawValue) \(RulesPreviewDebugLog.describe(scope: scope)) injectedPreferences=\(injectedPreferences != nil)"
            )
        }
        let preferenceOutcome = await TradingRulesCompliancePreferencesCache.load(
            for: profileID,
            repository: dependencies.tradingPreferences,
            injected: injectedPreferences
        )
        let preferences: PreferenceRuleContext?
        let preferencesError: String?
        switch preferenceOutcome {
        case .loaded(let context):
            preferences = context
            preferencesError = nil
        case .failed(let message):
            preferences = nil
            preferencesError = message
        case .skipped:
            preferences = nil
            preferencesError = "Trading rules could not be loaded."
        }

        var ownerTrades: [Trade]
        var tradesError: String?
        var historyComplete: Bool

        if TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome {
            if let preview = TraxsProPreviewSession.shared.activePreviewEnvironment,
               preview.viewer == profileID
            {
                ownerTrades = preview.trades
            } else {
                ownerTrades = DemoCanonicalDataset.trades()
            }
            historyComplete = true
        } else {
            ownerTrades = SessionOwnerTradesStore.shared.cached(for: profileID) ?? []
            historyComplete = SessionOwnerTradesStore.shared.isCompleteSnapshot(for: profileID)

            _ = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
                for: profileID,
                detailCache: dependencies.detailCache
            )
            ownerTrades = SessionOwnerTradesStore.shared.cached(for: profileID) ?? ownerTrades
            historyComplete = SessionOwnerTradesStore.shared.isCompleteSnapshot(for: profileID)
        }

        if !TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome,
           !historyComplete || ownerTrades.isEmpty
        {
            do {
                ownerTrades = try await SessionOwnerTradesStore.shared.ensureCompleteAnalyticsSnapshot(
                    for: profileID,
                    detailCache: dependencies.detailCache,
                    repository: dependencies.tradesRepository
                )
                historyComplete = SessionOwnerTradesStore.shared.isCompleteSnapshot(for: profileID)
            } catch {
                tradesError = "Check your connection and try again."
                if ownerTrades.isEmpty {
                    return Output(
                        result: nil,
                        hasConfiguredRules: false,
                        scopedTradeCount: 0,
                        ownerTradeCount: 0,
                        preferencesContext: preferences,
                        preferencesError: preferencesError,
                        tradesError: tradesError,
                        insufficientScope: false,
                        historyComplete: historyComplete,
                        eligibility: nil
                    )
                }
            }
        }

        let scoped = PsychologyAnalyticsTradeScope.complianceScopedTrades(
            ownerTrades: ownerTrades,
            accounts: accounts,
            scope: scope.filter
        )

        let allowedRuleIDs = ProMonetizationPolicy.tradingRulesComplianceRuleFilter(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: profileID
        )
        let isFreeTier = allowedRuleIDs != nil
        let hasRules = TradingRulesPlanTier.hasConfiguredRules(
            context: preferences,
            isFreeTier: isFreeTier
        )

        if preferencesError != nil {
            return Output(
                result: nil,
                hasConfiguredRules: hasRules,
                scopedTradeCount: scoped.count,
                ownerTradeCount: ownerTrades.count,
                preferencesContext: preferences,
                preferencesError: preferencesError,
                tradesError: tradesError,
                insufficientScope: false,
                historyComplete: historyComplete,
                eligibility: nil
            )
        }

        if hasRules, scoped.isEmpty {
            let ruleFamilies = TradingRulesComplianceDiagnostics.configuredRuleFamilyCount(context: preferences)
            let diag = TradingRulesComplianceDiagnostics.Snapshot(
                scopedTradeCount: 0,
                ownerTradeCount: ownerTrades.count,
                configuredRuleFamilies: ruleFamilies,
                evaluatedChecks: 0,
                violations: 0,
                followed: 0,
                unevaluated: 0,
                preferencesLoaded: preferences != nil,
                historyComplete: historyComplete
            )
            TradingRulesComplianceDiagnostics.log(diag)
            return Output(
                result: nil,
                hasConfiguredRules: true,
                scopedTradeCount: 0,
                ownerTradeCount: ownerTrades.count,
                preferencesContext: preferences,
                preferencesError: nil,
                tradesError: tradesError,
                insufficientScope: true,
                historyComplete: historyComplete,
                eligibility: nil
            )
        }

        guard hasRules, !scoped.isEmpty else {
            return Output(
                result: nil,
                hasConfiguredRules: hasRules,
                scopedTradeCount: scoped.count,
                ownerTradeCount: ownerTrades.count,
                preferencesContext: preferences,
                preferencesError: nil,
                tradesError: tradesError,
                insufficientScope: false,
                historyComplete: historyComplete,
                eligibility: nil
            )
        }

        let prepared = TradingRulesComplianceDisciplineContextBuilder.prepare(
            ownerTrades: ownerTrades,
            accounts: accounts,
            scopeFilter: scope.filter,
            preferences: preferences,
            historyComplete: historyComplete
        )
        if prepared.requiresCompleteHistoryForPsychology, !historyComplete {
            return Output(
                result: nil,
                hasConfiguredRules: hasRules,
                scopedTradeCount: scoped.count,
                ownerTradeCount: ownerTrades.count,
                preferencesContext: preferences,
                preferencesError: preferencesError,
                tradesError: "Loading complete trade history for psychology rule checks.",
                insufficientScope: false,
                historyComplete: false,
                eligibility: nil
            )
        }
        let discipline = prepared.discipline
        let payload = await TradingRulesComplianceCompute.computeScoped(
            trades: scoped,
            context: preferences,
            dashboardInsights: dashboardInsights,
            preferDashboardInsightsCache: dashboardInsights != nil,
            discipline: discipline,
            allowedRuleIDs: allowedRuleIDs
        )
        TradingRulesComplianceDiagnostics.logTimings(payload.timings, source: "cold_analytics")

        let built = assembleOutput(
            payload: payload,
            preferences: preferences,
            scopedTradeCount: scoped.count,
            ownerTradeCount: ownerTrades.count,
            tradesError: tradesError,
            insufficientScope: false,
            historyComplete: historyComplete,
            isAuthoritative: historyComplete
        )
        if previewChromeActive {
            RulesPreviewDebugLog.log(
                "SnapshotBuilder.build completed \(RulesPreviewDebugLog.describe(output: built))"
            )
        }
        return built
    }

    /// Dashboard quick pass over already-filtered trades (compute runs off the main actor).
    static func buildFromScopedTrades(
        trades: [Trade],
        scope: PsychologyAnalyticsScopeResolver.Resolved,
        preferences: PreferenceRuleContext?,
        accounts: [TradingAccount] = [],
        ownerTrades: [Trade]? = nil,
        historyComplete: Bool = false,
        dashboardInsights: DashboardInsightsPresentation? = nil,
        allowedRuleIDs: Set<TradingRulesComplianceAnalytics.RuleID>? = nil
    ) async -> Output {
        let isFreeTier = allowedRuleIDs != nil
        let hasRules = TradingRulesPlanTier.hasConfiguredRules(
            context: preferences,
            isFreeTier: isFreeTier
        )

        if hasRules, trades.isEmpty {
            return Output(
                result: nil,
                hasConfiguredRules: true,
                scopedTradeCount: 0,
                ownerTradeCount: 0,
                preferencesContext: preferences,
                preferencesError: nil,
                tradesError: nil,
                insufficientScope: true,
                historyComplete: false,
                eligibility: nil
            )
        }

        guard hasRules, !trades.isEmpty else {
            return Output(
                result: nil,
                hasConfiguredRules: hasRules,
                scopedTradeCount: trades.count,
                ownerTradeCount: trades.count,
                preferencesContext: preferences,
                preferencesError: nil,
                tradesError: nil,
                insufficientScope: false,
                historyComplete: false,
                eligibility: nil
            )
        }

        let owner = ownerTrades ?? trades
        let prepared = TradingRulesComplianceDisciplineContextBuilder.prepare(
            ownerTrades: owner,
            accounts: accounts,
            scopeFilter: scope.filter,
            preferences: preferences,
            historyComplete: historyComplete
        )
        if prepared.requiresCompleteHistoryForPsychology, !historyComplete {
            return Output(
                result: nil,
                hasConfiguredRules: true,
                scopedTradeCount: trades.count,
                ownerTradeCount: owner.count,
                preferencesContext: preferences,
                preferencesError: nil,
                tradesError: "Loading complete trade history for psychology rule checks.",
                insufficientScope: false,
                historyComplete: false,
                eligibility: nil
            )
        }

        let payload = await TradingRulesComplianceCompute.computeScoped(
            trades: trades,
            context: preferences,
            dashboardInsights: dashboardInsights,
            preferDashboardInsightsCache: dashboardInsights != nil,
            discipline: prepared.discipline,
            allowedRuleIDs: allowedRuleIDs
        )
        TradingRulesComplianceDiagnostics.logTimings(payload.timings, source: "dashboard")

        return assembleOutput(
            payload: payload,
            preferences: preferences,
            scopedTradeCount: trades.count,
            ownerTradeCount: owner.count,
            tradesError: nil,
            insufficientScope: false,
            historyComplete: historyComplete,
            isAuthoritative: historyComplete
        )
    }

    static func outputFromComputedPayload(
        payload: TradingRulesComplianceCompute.ScopedPayload,
        preferences: PreferenceRuleContext?,
        scopedTradeCount: Int,
        ownerTradeCount: Int,
        historyComplete: Bool,
        isAuthoritative: Bool? = nil
    ) -> Output {
        assembleOutput(
            payload: payload,
            preferences: preferences,
            scopedTradeCount: scopedTradeCount,
            ownerTradeCount: ownerTradeCount,
            tradesError: nil,
            insufficientScope: false,
            historyComplete: historyComplete,
            isAuthoritative: isAuthoritative ?? historyComplete
        )
    }

    private static func assembleOutput(
        payload: TradingRulesComplianceCompute.ScopedPayload,
        preferences: PreferenceRuleContext?,
        scopedTradeCount: Int,
        ownerTradeCount: Int,
        tradesError: String?,
        insufficientScope: Bool,
        historyComplete: Bool,
        isAuthoritative: Bool
    ) -> Output {
        let ruleFamilies = TradingRulesComplianceDiagnostics.configuredRuleFamilyCount(context: preferences)
        TradingRulesComplianceDiagnostics.logEligibility(payload.eligibility)
        let diag = TradingRulesComplianceDiagnostics.Snapshot(
            scopedTradeCount: scopedTradeCount,
            ownerTradeCount: ownerTradeCount,
            configuredRuleFamilies: ruleFamilies,
            evaluatedChecks: payload.result.score.evaluated,
            violations: payload.result.score.violated,
            followed: payload.result.score.followed,
            unevaluated: payload.result.score.unevaluated,
            preferencesLoaded: preferences != nil,
            historyComplete: historyComplete
        )
        TradingRulesComplianceDiagnostics.log(diag)

        return Output(
            result: insufficientScope ? nil : payload.result,
            hasConfiguredRules: TradingRulesComplianceSupport.hasConfiguredRules(context: preferences),
            scopedTradeCount: scopedTradeCount,
            ownerTradeCount: ownerTradeCount,
            preferencesContext: preferences,
            preferencesError: nil,
            tradesError: tradesError,
            insufficientScope: insufficientScope,
            historyComplete: historyComplete,
            eligibility: payload.eligibility,
            personalInsights: payload.personalInsights,
            isAuthoritative: isAuthoritative
        )
    }
}
