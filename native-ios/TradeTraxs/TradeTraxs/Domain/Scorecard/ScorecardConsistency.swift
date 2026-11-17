import Foundation

nonisolated enum ScorecardConsistency {
    static func score(
        trades: [ScorecardTrade],
        tradingDayCount: Int,
        postTripleLossWinRate: Double?
    ) -> ScorecardCategoryResult {
        _ = tradingDayCount
        _ = postTripleLossWinRate
        let weight = ScorecardConstants.categoryWeights[.consistency] ?? 0.25
        var subMetrics: [ScorecardSubMetric] = []
        var dataGaps: [String] = []

        let postLoss = ScorecardPlanAdherence.postLossPlanObservations(trades: trades)
        if let postLossRate = ScorecardPlanAdherence.planAdherenceRate(observations: postLoss), !postLoss.isEmpty {
            subMetrics.append(
                ScorecardSubMetric(
                    id: "consistency.plan_after_loss",
                    label: "Plan followed after a loss",
                    value: ScorecardReliabilitySupport.formatPercent(postLossRate),
                    explanation: "Share of tagged trades taken immediately after a loss where the plan was followed.",
                    sampleSize: postLoss.count,
                    sampleLabel: "post-loss tags"
                )
            )
        }

        let pool = ScorecardPlanAdherence.consistencyPlanAdherencePool(trades: trades)
        let poolRate = ScorecardPlanAdherence.planAdherenceRate(observations: pool.observations)
        var score: Int?
        if pool.observations.count >= ScorecardPlanAdherence.minPostLossPlanTagged, let poolRate {
            score = ScorecardReliabilitySupport.clampScore(poolRate * 100)
        } else if !trades.isEmpty {
            dataGaps.append(
                "Tag plan followed or not followed on at least \(ScorecardPlanAdherence.minPostLossPlanTagged) trades immediately after a loss."
            )
        }

        let reliability: ScorecardReliability =
            pool.observations.count >= ScorecardPlanAdherence.minPostLossPlanTagged
            ? ScorecardReliabilitySupport.resolve(sampleSize: pool.observations.count)
            : .insufficient
        let eligible = score != nil

        return ScorecardCategoryResult(
            id: .consistency,
            title: "Consistency",
            weight: weight,
            score: eligible ? score : nil,
            coveragePercent: eligible ? (score ?? 0) : 0,
            reliability: reliability,
            eligible: eligible,
            subMetrics: subMetrics,
            strengths: [],
            weaknesses: [],
            dataGaps: dataGaps
        )
    }
}
