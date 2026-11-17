import Foundation

/// Scorecard progress and the two insights that the adherence data can support.
/// Mirrors `lib/scorecard/readout.ts`.
nonisolated enum ScorecardReadout {
    private static let minPlanTags = 3
    private static let minPlanGap = 0.08
    private static let minRrPairs = 5
    private static let maxShortAttainment = 0.8

    static func adherence(
        trades: [ScorecardTrade],
        checkIns: [TraderDailyCheckIn]
    ) -> [ScorecardAdherenceReadout] {
        let tagged = trades.filter { $0.followedPlan != nil }
        let followed = tagged.filter { $0.followedPlan == true }.count
        let postLoss = ScorecardPlanAdherence.postLossPlanObservations(trades: trades)
        let postLossFollowed = postLoss.filter(\.followed).count
        let coverage = checkInCoverage(trades: trades, checkIns: checkIns)

        return [
            planReadout(
                id: "plan_overall",
                label: "Plan followed",
                followed: followed,
                tagged: tagged.count,
                minimum: minPlanTags,
                pendingNoun: "tagged trades"
            ),
            planReadout(
                id: "plan_after_loss",
                label: "After a loss",
                followed: postLossFollowed,
                tagged: postLoss.count,
                minimum: ScorecardPlanAdherence.minPostLossPlanTagged,
                pendingNoun: "post-loss tags"
            ),
            ScorecardAdherenceReadout(
                id: "check_in",
                label: "Check-ins",
                value: coverage.tradingDays > 0
                    ? "\(coverage.matchedDays) of \(coverage.tradingDays) trading days"
                    : "No trading days in this scope",
                pending: nil,
                sample: nil
            ),
        ]
    }

    static func insights(
        trades: [ScorecardTrade],
        preferences: PreferenceRuleContext? = nil
    ) -> [ScorecardInsight] {
        var insights: [ScorecardInsight] = []
        let tagged = trades.filter { $0.followedPlan != nil }
        let postLoss = ScorecardPlanAdherence.postLossPlanObservations(trades: trades)
        let overallRate = tagged.isEmpty
            ? nil
            : Double(tagged.filter { $0.followedPlan == true }.count) / Double(tagged.count)
        let afterRate = ScorecardPlanAdherence.planAdherenceRate(observations: postLoss)
        if let overallRate, let afterRate,
           tagged.count >= minPlanTags,
           postLoss.count >= ScorecardPlanAdherence.minPostLossPlanTagged,
           afterRate <= overallRate - minPlanGap
        {
            insights.append(
                ScorecardInsight(
                    id: "plan_after_loss",
                    text: "Plan adherence has been lower on trades taken after a loss. A pause before the next trade may help you stay with the plan. Based on \(postLoss.count) post-loss tags and \(tagged.count) tagged trades."
                )
            )
        }

        let paired = trades.compactMap { trade -> Double? in
            guard let target = trade.rr, target.isFinite, target > 0, let maxRr = trade.maxRrReached, maxRr.isFinite else {
                return nil
            }
            return maxRr / target
        }
        let personal = PreferenceComplianceEngine.evaluate(
            trades.map { trade in
                let at = Date(timeIntervalSince1970: Double(trade.entryTimeMs) / 1000)
                return PreferenceComplianceEngine.Input(
                    tradeID: trade.id,
                    at: at,
                    accountID: nil,
                    session: nil,
                    symbol: nil,
                    pnl: nil,
                    easternMinute: TradingSessionLabel.easternMinutesSinceMidnight(on: at),
                    dayKey: TradingSessionLabel.easternTradeDateString(from: at),
                    weekKey: TradingRuleScopeMath.easternWeekKey(from: at),
                    weekday: TradingRuleScopeMath.easternWeekday(from: at),
                    maxRr: trade.maxRrReached,
                    plannedRr: trade.rr.flatMap { $0 > 0 ? $0 : nil },
                    contracts: nil,
                    dollarRisk: trade.dollarRisk
                )
            },
            context: preferences
        )
        if let target = personal.uniformTargetRr,
           let maxRr = personal.avgMaxRr,
           maxRr < target,
           personal.targetPaired >= minRrPairs {
            insights.append(
                ScorecardInsight(
                    id: "max_r_shortfall",
                    text: "Average max R was \(PreferenceComplianceEngine.formatR(maxRr)), short of your \(PreferenceComplianceEngine.formatR(target))R target. Based on \(personal.targetPaired) trades with a recorded max R."
                )
            )
        } else if personal.targetPaired == 0, paired.count >= minRrPairs {
            let ratio = paired.reduce(0, +) / Double(paired.count)
            if ratio < maxShortAttainment {
                insights.append(
                    ScorecardInsight(
                        id: "max_r_shortfall",
                        text: "Maximum favorable R has been coming in short of the planned target. Reviewing whether those targets are realistic may help. Based on \(paired.count) trades with both a target and a max R."
                    )
                )
            }
        }
        return insights
    }

    private static func checkInCoverage(
        trades: [ScorecardTrade],
        checkIns: [TraderDailyCheckIn]
    ) -> (matchedDays: Int, tradingDays: Int) {
        let complete = Set(checkIns.filter(\.isComplete).map(\.checkInDate))
        var tradingDays = Set<String>()
        var matchedDays = Set<String>()
        for trade in trades {
            guard let key = trade.psychologyDayKey, !key.isEmpty else { continue }
            tradingDays.insert(key)
            if complete.contains(key) {
                matchedDays.insert(key)
            }
        }
        return (matchedDays.count, tradingDays.count)
    }

    private static func planReadout(
        id: String,
        label: String,
        followed: Int,
        tagged: Int,
        minimum: Int,
        pendingNoun: String
    ) -> ScorecardAdherenceReadout {
        if tagged >= minimum {
            return ScorecardAdherenceReadout(
                id: id,
                label: label,
                value: ScorecardReliabilitySupport.formatPercent(Double(followed) / Double(tagged)),
                pending: nil,
                sample: "\(tagged) \(pendingNoun)"
            )
        }
        return ScorecardAdherenceReadout(
            id: id,
            label: label,
            value: nil,
            pending: "\(tagged) of \(minimum) \(pendingNoun)",
            sample: nil
        )
    }
}
