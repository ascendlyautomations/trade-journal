import Foundation

/// Personal rule / discipline insights for Trading Rules Analytics.
nonisolated enum TradingRulesPersonalInsights {
    private static let disciplineIDs: Set<String> = [
        "client.risk.rr_threshold",
        "rr_threshold",
    ]

    static func resolve(
        dashboardPresentation: DashboardInsightsPresentation?,
        preferDashboardCache: Bool,
        trades: [Trade],
        preferences: PreferenceRuleContext?,
        compliance: TradingRulesComplianceAnalytics.Result? = nil
    ) -> [DashboardInsightItem] {
        var items: [DashboardInsightItem] = []

        if let compliance {
            items.append(contentsOf: complianceInsights(from: compliance))
        }

        if preferDashboardCache,
           let presentation = dashboardPresentation,
           !presentation.isLoading
        {
            let cached = sorted(filterRelevant(presentation.riskBehavior))
            if !cached.isEmpty {
                items.append(contentsOf: cached)
                return dedupedSorted(items)
            }
        }
        guard !trades.isEmpty else { return dedupedSorted(items) }
        let computed = sorted(
            filterRelevant(
                DashboardClientInsights.behaviorWarnings(from: trades, preferences: preferences)
            )
        )
        items.append(contentsOf: computed)
        return dedupedSorted(items)
    }

    static func relatedRuleLabel(for item: DashboardInsightItem) -> String? {
        if item.id == "tradingRules.waitAfterLoss" { return "Wait after loss" }
        if item.id == "tradingRules.consecutiveLossPause" { return "Consecutive loss pause" }
        if item.id == "tradingRules.periodChange" { return "Compliance trend" }
        if item.id == "tradingRules.mostBroken" { return "Rule compliance" }
        if item.id == "client.risk.loss_streak" || item.id == "loss_streak" {
            return "Consecutive loss pause"
        }
        if item.id == "client.risk.rr_threshold" || item.id == "rr_threshold" {
            return "Planned R:R discipline"
        }
        if item.id.hasPrefix("client.risk.preference.") {
            return ruleLabelFromPreferenceLine(item.displayBody)
        }
        return nil
    }

    private static func complianceInsights(
        from result: TradingRulesComplianceAnalytics.Result
    ) -> [DashboardInsightItem] {
        var items: [DashboardInsightItem] = []
        let progress = result.disciplineProgress

        if progress.periodCompareSufficient, let delta = progress.adherenceDeltaPoints {
            let direction = delta >= 0 ? "improved" : "declined"
            items.append(
                DashboardInsightItem(
                    id: "tradingRules.periodChange",
                    title: "Compliance trend",
                    body: "Your compliance \(direction) by \(String(format: "%.1f", abs(delta))) percentage points compared with the previous period.",
                    kind: .direction,
                    tone: delta >= 0 ? .positive : .warning,
                    section: .riskBehavior
                )
            )
        }

        if let top = result.violationPatterns.mostBrokenRules.first(where: { $0.violated > 0 }) {
            items.append(
                DashboardInsightItem(
                    id: "tradingRules.mostBroken",
                    title: "Most broken rule",
                    body: "Your most frequently violated rule was \(top.ruleLabel) (\(top.violated) violations among \(top.evaluated) evaluated checks).",
                    kind: .direction,
                    tone: .warning,
                    section: .riskBehavior
                )
            )
        }

        if let waitRow = result.impacts.first(where: { $0.ruleID == .waitAfterLoss }),
           waitRow.followed.priced + waitRow.violated.priced > 0
        {
            let evaluated = waitRow.followed.priced + waitRow.violated.priced
            items.append(
                DashboardInsightItem(
                    id: "tradingRules.waitAfterLoss",
                    title: "Wait after loss",
                    body: "You followed your waiting-after-loss rule on \(waitRow.followed.priced) of \(evaluated) evaluated occasions.",
                    kind: .direction,
                    tone: waitRow.violated.priced > waitRow.followed.priced ? .warning : .positive,
                    section: .riskBehavior
                )
            )
        }

        if let pauseRow = result.impacts.first(where: { $0.ruleID == .consecutiveLossPause }),
           pauseRow.violated.priced > 0
        {
            items.append(
                DashboardInsightItem(
                    id: "tradingRules.consecutiveLossPause",
                    title: "Consecutive loss pause",
                    body: "You entered \(pauseRow.violated.priced) trades at or after your consecutive-loss pause threshold while it was active.",
                    kind: .direction,
                    tone: .warning,
                    section: .riskBehavior
                )
            )
        }

        if progress.evaluatedDaysInScope > 0 {
            items.append(
                DashboardInsightItem(
                    id: "tradingRules.goalProgress",
                    title: "Compliance goal",
                    body: "\(progress.daysMeetingGoal) of \(progress.evaluatedDaysInScope) evaluated trading days met your \(Int(progress.goalPercent))% goal.",
                    kind: .direction,
                    tone: progress.daysMeetingGoal >= progress.evaluatedDaysInScope / 2 ? .positive : .neutral,
                    section: .riskBehavior
                )
            )
        }

        return items
    }

    private static func filterRelevant(_ items: [DashboardInsightItem]) -> [DashboardInsightItem] {
        items.filter { item in
            if item.id == "client.risk.loss_streak" || item.id == "loss_streak" { return false }
            if item.id.hasPrefix("client.risk.preference.") { return true }
            return disciplineIDs.contains(item.id)
        }
    }

    private static func dedupedSorted(_ items: [DashboardInsightItem]) -> [DashboardInsightItem] {
        var seen: Set<String> = []
        let unique = items.filter { seen.insert($0.id).inserted }
        return sorted(unique)
    }

    private static func sorted(_ items: [DashboardInsightItem]) -> [DashboardInsightItem] {
        items.sorted { lhs, rhs in
            let lk = sortRank(lhs)
            let rk = sortRank(rhs)
            if lk != rk { return lk < rk }
            return lhs.id < rhs.id
        }
    }

    private static func sortRank(_ item: DashboardInsightItem) -> Int {
        switch item.id {
        case "tradingRules.periodChange": return 10
        case "tradingRules.mostBroken": return 20
        case "tradingRules.waitAfterLoss": return 30
        case "tradingRules.consecutiveLossPause": return 40
        case "tradingRules.goalProgress": return 50
        default: break
        }
        if item.id.hasPrefix("client.risk.preference.") {
            if let suffix = item.id.split(separator: ".").last, let index = Int(suffix) {
                return 1_000 + index
            }
            return 1_000
        }
        switch item.id {
        case "client.risk.rr_threshold", "rr_threshold": return 2_000
        default: return 3_000
        }
    }

    private static func ruleLabelFromPreferenceLine(_ body: String) -> String {
        let lower = body.lowercased()
        if lower.contains("preferred session") { return "Preferred sessions" }
        if lower.contains("primary instrument") { return "Primary instruments" }
        if lower.contains("planned trading hours") || lower.contains("planned hours") {
            return "Planned trading hours"
        }
        if lower.contains("allowed trading day") { return "Allowed trading days" }
        if lower.contains("max trades") || lower.contains("daily trade cap") || lower.contains("trades per day") {
            return TradingRulesDisplayLabels.maxTradesPerDay
        }
        if lower.contains("daily loss limit") { return "Daily loss limit" }
        if lower.contains("profit target") { return "Daily profit target" }
        if lower.contains("weekly loss") { return "Weekly loss limit" }
        if lower.contains("maximum contracts") || lower.contains("max contracts") {
            return TradingRulesDisplayLabels.maxContracts
        }
        if lower.contains("minimum acceptable r") || lower.contains("min acceptable r")
            || lower.contains("planned r:r") || lower.contains("min planned r") {
            return TradingRulesDisplayLabels.minPlannedRr
        }
        if lower.contains("maximum risk per trade") || lower.contains("max risk per trade")
            || lower.contains("max risk / trade") || lower.contains("dollar risk") {
            return TradingRulesDisplayLabels.maxRiskPerTrade
        }
        if lower.contains("wait") && lower.contains("loss") { return "Wait after loss" }
        if lower.contains("consecutive") && lower.contains("loss") { return "Consecutive loss pause" }
        if lower.contains("personal rules") || lower.contains("inside your") {
            return "Personal rules"
        }
        return "Personal rules"
    }
}
