import Foundation

/// Free vs TraxsPro Trading Rules, rule families and settings copy (presentation + client compliance scope).
nonisolated enum TradingRulesPlanTier {
    typealias RuleID = TradingRulesComplianceAnalytics.RuleID

  /// Configurable on TradeTraxs Free (compliance scoring uses these families only when enforcement is on).
    static let freeRuleIDs: Set<RuleID> = [
        .preferredSession,
        .allowedTradingDay,
        .maxTradesPerDay,
        .maxContracts,
        .primaryInstrument,
    ]

    static let premiumRuleIDs: Set<RuleID> = Set(RuleID.allCases).subtracting(freeRuleIDs)

    enum PremiumRuleCategory: String, CaseIterable, Sendable {
        case riskManagement = "Risk Management"
        case tradingDiscipline = "Trading Discipline"
        case performanceTargets = "Performance Targets"
    }

    struct PremiumRuleCard: Identifiable, Sendable, Hashable {
        var id: String { ruleID.rawValue }
        let ruleID: RuleID
        let category: PremiumRuleCategory
        let title: String
        let detail: String
        let systemImage: String
    }

    static let premiumRuleCards: [PremiumRuleCard] = [
        PremiumRuleCard(
            ruleID: .maxRiskPerTrade,
            category: .riskManagement,
            title: TradingRulesDisplayLabels.maxRiskPerTrade,
            detail: "Cap dollar risk on each entry against your plan.",
            systemImage: "dollarsign.circle"
        ),
        PremiumRuleCard(
            ruleID: .dailyLossLimit,
            category: .riskManagement,
            title: "Daily loss limit",
            detail: "Stop trading after your daily loss stop is breached.",
            systemImage: "chart.line.downtrend.xyaxis"
        ),
        PremiumRuleCard(
            ruleID: .dailyProfitStop,
            category: .riskManagement,
            title: "Daily profit stop",
            detail: "Walk away after hitting your daily profit target.",
            systemImage: "flag.checkered"
        ),
        PremiumRuleCard(
            ruleID: .weeklyLossLimit,
            category: .riskManagement,
            title: TradingRulesDisplayLabels.maxWeeklyLoss,
            detail: "Weekly cumulative loss guardrails across your scope.",
            systemImage: "calendar"
        ),
        PremiumRuleCard(
            ruleID: .consecutiveLossPause,
            category: .tradingDiscipline,
            title: "Consecutive loss pause",
            detail: "Pause entries after a streak of priced losses.",
            systemImage: "pause.circle"
        ),
        PremiumRuleCard(
            ruleID: .waitAfterLoss,
            category: .tradingDiscipline,
            title: "Wait after loss",
            detail: "Cooling-off period before new entries after a loss.",
            systemImage: "hourglass"
        ),
        PremiumRuleCard(
            ruleID: .minPlannedRr,
            category: .performanceTargets,
            title: TradingRulesDisplayLabels.minPlannedRr,
            detail: "Require a minimum reward-to-risk before entry.",
            systemImage: "arrow.up.right"
        ),
        PremiumRuleCard(
            ruleID: .targetRrMax,
            category: .performanceTargets,
            title: "Target R:R",
            detail: "Compare max R reached against your target.",
            systemImage: "target"
        ),
        PremiumRuleCard(
            ruleID: .plannedHours,
            category: .performanceTargets,
            title: "Planned trading hours",
            detail: "Score trades outside your planned start and end window.",
            systemImage: "clock"
        ),
    ]

    static func premiumRuleCards(for category: PremiumRuleCategory) -> [PremiumRuleCard] {
        premiumRuleCards.filter { $0.category == category }
    }

    /// @deprecated Use ``premiumRuleCards``, kept for brief upsell lists.
    static var premiumRuleSummaries: [PremiumRuleCard] { premiumRuleCards }

    /// `nil` = evaluate all rule families (TraxsPro).
    static func complianceRuleFilter(isFreeTier: Bool) -> Set<RuleID>? {
        isFreeTier ? freeRuleIDs : nil
    }

    static func hasConfiguredFreeTierRules(context: PreferenceRuleContext?) -> Bool {
        guard let global = context?.global else { return false }
        if !global.preferredSessions.isEmpty { return true }
        if !global.primaryInstruments.isEmpty { return true }
        if !TradingPreferenceRules.normalizeAllowedTradingDays(global.allowedTradingDays).isEmpty {
            return true
        }
        if global.maxTradesPerDay != nil { return true }
        if global.maxContractsPerTrade != nil { return true }
        return false
    }

    static func hasConfiguredRules(
        context: PreferenceRuleContext?,
        isFreeTier: Bool
    ) -> Bool {
        if isFreeTier {
            return hasConfiguredFreeTierRules(context: context)
        }
        return TradingRulesComplianceSupport.hasConfiguredRules(context: context)
    }

    static func filterChecks(
        _ checks: [TradingRulesComplianceAnalytics.Check],
        allowedRuleIDs: Set<RuleID>?
    ) -> [TradingRulesComplianceAnalytics.Check] {
        guard let allowedRuleIDs else { return checks }
        return checks.filter { allowedRuleIDs.contains($0.ruleID) }
    }
}