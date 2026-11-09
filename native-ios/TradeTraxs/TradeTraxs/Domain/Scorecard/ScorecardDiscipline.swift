import Foundation

nonisolated enum ScorecardDiscipline {
    static let minPlanTaggedForScore = 3
    private static let minCoverageWarningTrades = 5
    private static let minSecondaryInsight = 2

    static func score(trades: [ScorecardTrade]) -> ScorecardCategoryResult {
        let weight = ScorecardConstants.categoryWeights[.discipline] ?? 0.2
        var subMetrics: [ScorecardSubMetric] = []
        var strengths: [String] = []
        var weaknesses: [String] = []
        var dataGaps: [String] = []

        let withPlanKnown = trades.filter { $0.followedPlan != nil }
        let followed = withPlanKnown.filter { $0.followedPlan == true }
        let withConfidence = trades.filter { ($0.confidence ?? 0) >= 1 }
        let withExecution = trades.filter { ($0.executionRating ?? 0) >= 1 }
        let losses = trades.filter { $0.pnl < 0 }

        let planCoverage = trades.isEmpty ? 0 : Double(withPlanKnown.count) / Double(trades.count)
        subMetrics.append(
            ScorecardSubMetric(
                id: "discipline.plan_coverage",
                label: "Trades with plan follow-up logged",
                value: ScorecardReliabilitySupport.formatPercent(planCoverage),
                explanation:
                    "Share of trades with an explicit plan followed / not followed tag. Low coverage means the adherence score may not represent all behavior.",
                sampleSize: withPlanKnown.count,
                sampleLabel: "tagged trades"
            )
        )

        if planCoverage < 0.5, trades.count >= minCoverageWarningTrades {
            weaknesses.append(
                "Plan adherence is tagged on fewer than half of trades, interpret the score cautiously or tag more trades."
            )
        }

        var planScore: Int?
        if withPlanKnown.count >= minPlanTaggedForScore {
            let rate = Double(followed.count) / Double(withPlanKnown.count)
            planScore = ScorecardReliabilitySupport.clampScore(rate * 100)
            subMetrics.append(
                ScorecardSubMetric(
                    id: "discipline.plan_adherence",
                    label: "Plan followed (explicit tags only)",
                    value: ScorecardReliabilitySupport.formatPercent(rate),
                    explanation:
                        "Share of tagged trades where you marked the plan as followed, missing tags are excluded, not treated as violations.",
                    sampleSize: withPlanKnown.count,
                    sampleLabel: "tagged trades"
                )
            )
            if rate >= 0.7 {
                strengths.append("You report following your plan on most explicitly tagged trades.")
            }
            if rate < 0.45 {
                weaknesses.append("Plan adherence is low on tagged trades, review rules and triggers.")
            }
        } else {
            dataGaps.append(
                "Tag plan followed / not followed on at least \(minPlanTaggedForScore) trades to score discipline."
            )
        }

        if losses.count >= minSecondaryInsight {
            let mistakeOnLoss = Double(losses.filter { ($0.mistakeType ?? "").isEmpty == false }.count)
                / Double(losses.count)
            subMetrics.append(
                ScorecardSubMetric(
                    id: "discipline.mistake_logging_coverage",
                    label: "Losses with mistake type logged (coverage)",
                    value: ScorecardReliabilitySupport.formatPercent(mistakeOnLoss),
                    explanation:
                        "Review documentation on losses, logging mistakes supports learning and is not scored as mistake avoidance.",
                    sampleSize: losses.count,
                    sampleLabel: "losing trades"
                )
            )
        }

        if withConfidence.count >= minSecondaryInsight {
            subMetrics.append(
                ScorecardSubMetric(
                    id: "discipline.confidence_coverage",
                    label: "Trades with confidence logged (coverage)",
                    value: ScorecardReliabilitySupport.formatPercent(
                        Double(withConfidence.count) / Double(trades.count)
                    ),
                    explanation: "Confidence tags are optional context, not part of the discipline score.",
                    sampleSize: withConfidence.count,
                    sampleLabel: "tagged trades"
                )
            )
        }

        if withExecution.count >= minSecondaryInsight {
            let avg = withExecution.reduce(0.0) { $0 + ($1.executionRating ?? 0) } / Double(withExecution.count)
            subMetrics.append(
                ScorecardSubMetric(
                    id: "discipline.execution_rating_coverage",
                    label: "Average execution self-rating (coverage)",
                    value: String(format: "%.1f / 5", avg),
                    explanation:
                        "Self-rated execution where logged, shown for transparency; not part of the discipline score.",
                    sampleSize: withExecution.count,
                    sampleLabel: "rated trades"
                )
            )
        }

        let coveragePercent = ScorecardReliabilitySupport.clampScore(
            trades.isEmpty ? 0 : Double(withPlanKnown.count) / Double(trades.count) * 100
        )
        let reliability = ScorecardReliabilitySupport.resolve(sampleSize: withPlanKnown.count)
        let eligible = withPlanKnown.count >= minPlanTaggedForScore && planScore != nil

        return ScorecardCategoryResult(
            id: .discipline,
            title: "Discipline",
            weight: weight,
            score: eligible ? planScore : nil,
            coveragePercent: coveragePercent,
            reliability: reliability,
            eligible: eligible,
            subMetrics: subMetrics,
            strengths: strengths,
            weaknesses: weaknesses,
            dataGaps: dataGaps
        )
    }
}
