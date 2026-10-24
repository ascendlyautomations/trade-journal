import Foundation

nonisolated struct DashboardInsightsPresentation: Sendable, Equatable {
    var isLoading: Bool
    var performance: [DashboardInsightItem]
    var advancedEdge: [DashboardInsightItem]
    var riskBehavior: [DashboardInsightItem]

    var isEmpty: Bool {
        performance.isEmpty && advancedEdge.isEmpty && riskBehavior.isEmpty
    }
}

/// Merges V3 server insights with web-parity client narratives (client first; server fills gaps only).
nonisolated enum DashboardInsightsComposer {
    static func build(
        serverInsights: [DashboardInsightItem],
        trades: [Trade],
        strategyHighlights: DashboardStrategyHighlights?,
        isLoading: Bool,
        tradeCount: Int
    ) -> DashboardInsightsPresentation {
        var performance: [DashboardInsightItem] = []
        var advancedEdge: [DashboardInsightItem] = []
        var riskBehavior: [DashboardInsightItem] = []
        var coverage = InsightTopicCoverage()

        if !trades.isEmpty {
            performance.append(contentsOf: DashboardClientInsights.performanceNarratives(from: trades))
            markCoverage(performance, into: &coverage)

            if let strategy = DashboardClientInsights.bestPerformingStrategyInsight(
                from: trades,
                highlights: strategyHighlights
            ) {
                advancedEdge.append(strategy)
                coverage.bestStrategy = true
            }

            advancedEdge.append(contentsOf: DashboardClientInsights.advancedEdge(from: trades))
            markCoverage(advancedEdge, into: &coverage)

            if let worst = DashboardClientInsights.worstCombinedSetup(from: trades) {
                riskBehavior.append(worst)
                coverage.worstSetup = true
            }
            riskBehavior.append(contentsOf: DashboardClientInsights.behaviorWarnings(from: trades))
            markCoverage(riskBehavior, into: &coverage)
        }

        for var insight in serverInsights {
            enrichServerInsight(&insight)
            guard trades.isEmpty || shouldIncludeServerInsight(insight, coverage: coverage) else {
                continue
            }
            switch insight.section {
            case .performance: performance.append(insight)
            case .advancedEdge: advancedEdge.append(insight)
            case .riskBehavior: riskBehavior.append(insight)
            }
        }

        let merged = DashboardInsightsPresentation(
            isLoading: false,
            performance: dedupe(performance),
            advancedEdge: dedupe(advancedEdge),
            riskBehavior: dedupe(riskBehavior)
        )
        if isLoading, merged.isEmpty, tradeCount > 0 {
            return DashboardInsightsPresentation(
                isLoading: true,
                performance: [],
                advancedEdge: [],
                riskBehavior: []
            )
        }
        return merged
    }

    private struct InsightTopicCoverage: Sendable {
        var session = false
        var symbol = false
        var direction = false
        var combinedEdge = false
        var bestStrategy = false
        var worstSetup = false
        var lossStreak = false
        var rrThreshold = false
    }

    private static func markCoverage(_ items: [DashboardInsightItem], into coverage: inout InsightTopicCoverage) {
        for item in items {
            switch item.id {
            case "client.performance.session": coverage.session = true
            case "client.performance.ticker": coverage.symbol = true
            case "client.performance.direction": coverage.direction = true
            case "client.advanced.combo": coverage.combinedEdge = true
            case "client.advanced.best_strategy": coverage.bestStrategy = true
            case "client.risk.worst_combo": coverage.worstSetup = true
            case "client.risk.loss_streak": coverage.lossStreak = true
            case "client.risk.rr_threshold": coverage.rrThreshold = true
            default: break
            }
        }
    }

    /// Server cards only when client narratives (same filters/trades) did not already cover the topic.
    private static func shouldIncludeServerInsight(
        _ insight: DashboardInsightItem,
        coverage: InsightTopicCoverage
    ) -> Bool {
        switch insight.id {
        case "session_edge", "session":
            return !coverage.session
        case "symbol":
            return !coverage.symbol
        case "direction_long", "direction_short", "direction":
            return !coverage.direction
        case "strategy_best":
            return !coverage.bestStrategy
        case "strategy_worst":
            return !coverage.worstSetup
        case "loss_streak":
            return !coverage.lossStreak
        case "rr_threshold":
            return !coverage.rrThreshold
        case "symbol_weak":
            return true
        default:
            return true
        }
    }

    private static func enrichServerInsight(_ insight: inout DashboardInsightItem) {
        switch insight.id {
        case "session_edge", "symbol":
            insight.section = .performance
            insight.tone = .positive
        case "strategy_best":
            insight.section = .advancedEdge
            insight.tone = .positive
        case "symbol_weak":
            insight.section = .riskBehavior
            insight.tone = .negative
        case "strategy_worst":
            insight.section = .riskBehavior
            insight.tone = .negative
        case "loss_streak", "rr_threshold":
            insight.section = .riskBehavior
            insight.tone = .warning
        case "direction_long", "direction_short":
            insight.section = .performance
            insight.tone = .neutral
        default:
            insight.section = .performance
            insight.tone = .neutral
        }
    }

    private static func dedupe(_ items: [DashboardInsightItem]) -> [DashboardInsightItem] {
        var seen = Set<String>()
        var out: [DashboardInsightItem] = []
        for item in items {
            guard seen.insert(item.id).inserted else { continue }
            out.append(item)
        }
        return out
    }
}
