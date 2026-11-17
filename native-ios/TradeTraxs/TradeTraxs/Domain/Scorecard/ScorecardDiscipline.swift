import Foundation

nonisolated enum ScorecardDiscipline {
    static let minPlanTaggedForScore = 3

    static func score(trades: [ScorecardTrade]) -> ScorecardCategoryResult {
        let weight = ScorecardConstants.categoryWeights[.discipline] ?? 0.2
        var subMetrics: [ScorecardSubMetric] = []
        var dataGaps: [String] = []

        let withPlanKnown = trades.filter { $0.followedPlan != nil }
        let followed = withPlanKnown.filter { $0.followedPlan == true }

        subMetrics.append(
            ScorecardSubMetric(
                id: "discipline.plan_coverage",
                label: "Tagged trades",
                value: String(withPlanKnown.count),
                explanation: "Trades with an explicit plan followed or not followed tag.",
                sampleSize: withPlanKnown.count,
                sampleLabel: "tagged trades"
            )
        )

        var planScore: Int?
        if withPlanKnown.count >= minPlanTaggedForScore {
            let rate = Double(followed.count) / Double(withPlanKnown.count)
            planScore = ScorecardReliabilitySupport.clampScore(rate * 100)
            subMetrics.append(
                ScorecardSubMetric(
                    id: "discipline.plan_adherence",
                    label: "Plan followed",
                    value: ScorecardReliabilitySupport.formatPercent(rate),
                    explanation: "Share of tagged trades marked as plan followed. Missing tags are excluded.",
                    sampleSize: withPlanKnown.count,
                    sampleLabel: "tagged trades"
                )
            )
        } else if !trades.isEmpty {
            dataGaps.append("Tag plan followed or not followed on at least \(minPlanTaggedForScore) trades.")
        }

        let eligible = withPlanKnown.count >= minPlanTaggedForScore && planScore != nil
        return ScorecardCategoryResult(
            id: .discipline,
            title: "Discipline",
            weight: weight,
            score: eligible ? planScore : nil,
            coveragePercent: ScorecardReliabilitySupport.clampScore(
                trades.isEmpty ? 0 : Double(withPlanKnown.count) / Double(trades.count) * 100
            ),
            reliability: ScorecardReliabilitySupport.resolve(sampleSize: withPlanKnown.count),
            eligible: eligible,
            subMetrics: subMetrics,
            strengths: [],
            weaknesses: [],
            dataGaps: dataGaps
        )
    }
}
