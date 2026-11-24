import Foundation

/// Deterministic coaching copy, always available without AI.
nonisolated enum PsychologyCoachDeterministicCoach {
    static func buildSummary(from facts: PsychologyCoachFacts) -> PsychologyCoachSummary {
        guard facts.hasMinimumData else {
            return PsychologyCoachSummary(
                title: "Your Psychology",
                overview: facts.dataGaps.first ?? "Log more trades and daily check-ins to unlock personalized coaching.",
                doingWell: [],
                watchItems: [],
                recommendations: [],
                isDeterministic: true
            )
        }

        let overview = buildOverview(facts)
        let doingWell = positiveObservations(from: facts)
        let watchItems = watchObservations(from: facts)
        let recommendations = buildRecommendations(from: facts)

        return PsychologyCoachSummary(
            title: "Your Psychology",
            overview: overview,
            doingWell: Array(doingWell.prefix(3)),
            watchItems: Array(watchItems.prefix(4)),
            recommendations: Array(recommendations.prefix(4)),
            isDeterministic: true
        )
    }

    static func buildOverview(_ facts: PsychologyCoachFacts) -> String {
        var parts: [String] = []

        if let best = facts.topInsights.first(where: { $0.category == "sleep" || $0.category == "mentalState" }) {
            parts.append("Patterns in your check-in data suggest \(best.headline.lowercased()).")
        } else if let best = facts.topInsights.first {
            parts.append("Your data highlights: \(best.headline.lowercased()).")
        } else {
            parts.append("Keep logging trades with psychology tags to sharpen these insights.")
        }

        if facts.guardrailFacts.consecutiveLossCheckpoint != nil {
            parts.append("Your largest performance drop currently occurs after multiple consecutive losses.")
        }

        return parts.joined(separator: " ")
    }

    private static func positiveObservations(from facts: PsychologyCoachFacts) -> [String] {
        var items: [String] = []
        for insight in facts.topInsights {
            let headline = insight.headline.lowercased()
            let favorable = headline.contains("outperform")
                || headline.contains("strongest")
                || headline.contains("stable")
                || headline.contains("best")
                || headline.contains("performed better")
                || headline.contains("won more often")
            let unfavorable = headline.contains("in this sample")
                || headline.contains("worse")
                || headline.contains("less often")
            if favorable && !unfavorable {
                items.append(insight.headline)
            }
        }
        for trend in facts.trends where trend.headline.localizedCaseInsensitiveContains("improved")
            || trend.headline.localizedCaseInsensitiveContains("decreased") {
            items.append(trend.headline)
        }
        for combo in facts.combinedPatterns where combo.headline.localizedCaseInsensitiveContains("strongest") {
            items.append(combo.headline)
        }
        return items
    }

    private static func watchObservations(from facts: PsychologyCoachFacts) -> [String] {
        var items = facts.topInsights
            .filter {
                $0.headline.localizedCaseInsensitiveContains("drop")
                    || $0.headline.localizedCaseInsensitiveContains("weaker")
                    || $0.headline.localizedCaseInsensitiveContains("underperform")
                    || $0.headline.localizedCaseInsensitiveContains("worse")
                    || $0.headline.localizedCaseInsensitiveContains("less often")
                    || $0.headline.localizedCaseInsensitiveContains("in this sample")
            }
            .map(\.headline)
        for trend in facts.trends where trend.headline.localizedCaseInsensitiveContains("weakened")
            || trend.headline.localizedCaseInsensitiveContains("increased")
            || trend.headline.localizedCaseInsensitiveContains("slipped") {
            items.append(trend.headline)
        }
        return items
    }

    static func buildRecommendations(from facts: PsychologyCoachFacts) -> [String] {
        var recs: [String] = []

        if let checkpoint = facts.guardrailFacts.consecutiveLossCheckpoint {
            recs.append(
                facts.guardrailFacts.personalLossPause
                    ? "Results have been weaker after your pause of \(checkpoint) consecutive losses."
                    : "Results have been weaker after \(checkpoint) consecutive losses. That is a result difference, not a reason those trades were taken."
            )
        }

        if let limit = facts.guardrailFacts.maxTradesDaySoftLimit {
            recs.append(
                facts.guardrailFacts.personalTradeCap
                    ? "Trades beyond your daily cap of \(limit) have been weaker than trades within it."
                    : "Later trades in the day have been weaker than your first three. Reviewing whether those extra setups are lower quality may help."
            )
        }

        if facts.guardrailFacts.lowSleepHoursThreshold != nil {
            recs.append(
                "Be cautious after fewer than 6 hours of sleep. Those sessions have been weaker than better-rested ones."
            )
        }

        if facts.guardrailFacts.highStressWeaker {
            recs.append(
                "Reset when stress is high. Lower-stress days have been the stronger ones."
            )
        }

        return recs
    }

    /// Fallback when AI is unavailable, explains a single insight in plain language.
    static func explainInsight(_ insight: PsychologyCoachFactInsight) -> String {
        "\(insight.headline). \(insight.detail) This is based on \(insight.sampleSize) trades (\(insight.reliability) signal). Associated patterns are not proof of causation."
    }
}
