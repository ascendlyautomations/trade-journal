import Foundation

nonisolated enum ScorecardConsistency {
    static func score(
        trades: [ScorecardTrade],
        tradingDayCount: Int,
        postTripleLossWinRate: Double?
    ) -> ScorecardCategoryResult {
        let weight = ScorecardConstants.categoryWeights[.consistency] ?? 0.25
        var subMetrics: [ScorecardSubMetric] = []
        var strengths: [String] = []
        var weaknesses: [String] = []
        var dataGaps: [String] = []

        let daysWithKeys = Set(trades.compactMap(\.tradingDayKey)).count

        if tradingDayCount < 5 {
            dataGaps.append("Log trades on at least 5 distinct trading days in this scope.")
        }

        subMetrics.append(
            ScorecardSubMetric(
                id: "consistency.active_trading_days",
                label: "Active trading days in scope",
                value: String(tradingDayCount),
                explanation:
                    "Days with at least one trade in this filter, sparse schedules and breaks are not penalized.",
                sampleSize: tradingDayCount,
                sampleLabel: "trading days"
            )
        )

        let postLoss = ScorecardPlanAdherence.postLossPlanObservations(trades: trades)
        if let postLossRate = ScorecardPlanAdherence.planAdherenceRate(observations: postLoss), !postLoss.isEmpty {
            subMetrics.append(
                ScorecardSubMetric(
                    id: "consistency.plan_after_loss",
                    label: "Plan followed after a loss (explicit tags)",
                    value: ScorecardReliabilitySupport.formatPercent(postLossRate),
                    explanation:
                        "Among trades immediately after a losing trade where you tagged plan adherence, behavioral consistency under pressure.",
                    sampleSize: postLoss.count,
                    sampleLabel: "tagged post-loss trades"
                )
            )
        }

        let tripleWindow = ScorecardPlanAdherence.tripleLossWindowPlanObservations(trades: trades)
        if let tripleWindowRate = ScorecardPlanAdherence.planAdherenceRate(observations: tripleWindow),
           tripleWindow.count >= ScorecardPlanAdherence.minTripleLossWindowPlanTagged
        {
            subMetrics.append(
                ScorecardSubMetric(
                    id: "consistency.plan_after_three_losses",
                    label: "Plan followed after 3-loss sequence (explicit tags)",
                    value: ScorecardReliabilitySupport.formatPercent(tripleWindowRate),
                    explanation:
                        "Tagged trades in the recovery window after the first 3-loss run, shown separately; not double-counted in the score pool.",
                    sampleSize: tripleWindow.count,
                    sampleLabel: "tagged trades in window"
                )
            )
        }

        if let postTripleLossWinRate {
            subMetrics.append(
                ScorecardSubMetric(
                    id: "streak.after_three_losses_win_rate",
                    label: "Win rate after 3 consecutive losses (outcome context)",
                    value: ScorecardReliabilitySupport.formatPercent(postTripleLossWinRate),
                    explanation:
                        "Performance context only, not part of the consistency score. Does not reflect plan tagging or calendar frequency.",
                    sampleSize: trades.count,
                    sampleLabel: "trades in scope"
                )
            )
            if postTripleLossWinRate < 0.45 {
                weaknesses.append(
                    "Win rate drops after 3 consecutive losses, consider a pause rule (outcome context)."
                )
            } else if postTripleLossWinRate >= 0.55 {
                strengths.append("Win rate after 3-loss sequences is stable in this sample (outcome context).")
            }
        }

        let pool = ScorecardPlanAdherence.consistencyPlanAdherencePool(trades: trades)
        let poolRate = ScorecardPlanAdherence.planAdherenceRate(observations: pool.observations)
        var score: Int?
        if pool.observations.count >= ScorecardPlanAdherence.minPostLossPlanTagged, let poolRate {
            score = ScorecardReliabilitySupport.clampScore(poolRate * 100)
            if pool.tripleWindowAddedCount > 0 {
                let explanationSuffix = pool.tripleWindowAddedCount > 0
                    ? " plus \(pool.tripleWindowAddedCount) additional tagged trade(s) from the 3-loss window without double-counting."
                    : "."
                subMetrics.append(
                    ScorecardSubMetric(
                        id: "consistency.scored_pool",
                        label: "Scored post-loss sample (deduplicated)",
                        value: ScorecardReliabilitySupport.formatPercent(poolRate),
                        explanation:
                            "\(pool.postLossCount) post-loss tagged trade(s)\(explanationSuffix)",
                        sampleSize: pool.observations.count,
                        sampleLabel: "tagged trades in score pool"
                    )
                )
            }
            if poolRate >= 0.7 {
                strengths.append("You often report following your plan on trades taken after losses.")
            } else if poolRate < 0.45 {
                weaknesses.append("Plan adherence drops on trades after losses, review pause rules and triggers.")
            }
        } else if trades.count >= 5 {
            dataGaps.append(
                "Tag plan followed / not followed on at least \(ScorecardPlanAdherence.minPostLossPlanTagged) trades immediately after a loss to score consistency."
            )
        }

        let reliability: ScorecardReliability =
            pool.observations.count >= ScorecardPlanAdherence.minPostLossPlanTagged
            ? ScorecardReliabilitySupport.resolve(sampleSize: pool.observations.count)
            : .insufficient

        let eligible =
            tradingDayCount >= 5
            && trades.count >= 5
            && score != nil
            && ScorecardReliabilitySupport.isDevelopingOrStrong(reliability)

        let coveragePercent =
            trades.isEmpty
            ? 0
            : ScorecardReliabilitySupport.clampScore(
                Double(daysWithKeys) / Double(max(tradingDayCount, 1)) * 100
            )

        return ScorecardCategoryResult(
            id: .consistency,
            title: "Consistency",
            weight: weight,
            score: eligible ? score : nil,
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
