import Foundation

nonisolated enum ScorecardRisk {
    static func score(
        trades: [ScorecardTrade],
        maxDrawdown: Double,
        avgWin: Double,
        avgLoss: Double,
        rrTarget: DashboardRrTargetAnalysis
    ) -> ScorecardCategoryResult {
        let weight = ScorecardConstants.categoryWeights[.risk] ?? 0.25
        var subMetrics: [ScorecardSubMetric] = []
        let strengths: [String] = []
        let weaknesses: [String] = []
        var dataGaps: [String] = []

        let withPlannedRr = trades.filter { ($0.rr ?? 0) > 0 }
        let withRealizedRr = trades.filter { $0.realizedRr != nil }
        let withMaxRr = trades.filter { ($0.maxRrReached ?? 0) > 0 }

        let rrCoverage = trades.isEmpty ? 0 : Double(withPlannedRr.count) / Double(trades.count)
        let realizedCoverage = trades.isEmpty ? 0 : Double(withRealizedRr.count) / Double(trades.count)
        let maxRrCoverage = trades.isEmpty ? 0 : Double(withMaxRr.count) / Double(trades.count)

        subMetrics.append(
            ScorecardSubMetric(
                id: "risk.planned_rr_coverage",
                label: "Trades with planned R:R logged",
                value: ScorecardReliabilitySupport.formatPercent(rrCoverage),
                explanation:
                    "Planned risk/reward target on the trade, documentation coverage only in Phase 1.",
                sampleSize: trades.count,
                sampleLabel: "trades"
            )
        )

        if !withRealizedRr.isEmpty {
            subMetrics.append(
                ScorecardSubMetric(
                    id: "risk.realized_rr_coverage",
                    label: "Trades with realized R:R",
                    value: ScorecardReliabilitySupport.formatPercent(realizedCoverage),
                    explanation:
                        "Realized R:R from stored exit data or plan/price math, not scored; does not validate stop placement.",
                    sampleSize: withRealizedRr.count,
                    sampleLabel: "trades"
                )
            )
        }

        if !withMaxRr.isEmpty {
            subMetrics.append(
                ScorecardSubMetric(
                    id: "risk.max_rr_coverage",
                    label: "Trades with max R reached logged",
                    value: ScorecardReliabilitySupport.formatPercent(maxRrCoverage),
                    explanation:
                        "Maximum favorable excursion vs plan, context for review; not exit quality or risk discipline.",
                    sampleSize: withMaxRr.count,
                    sampleLabel: "trades"
                )
            )
        }

        if rrCoverage < 0.25, trades.count >= 5 {
            dataGaps.append("Log planned R:R on more trades to improve risk documentation coverage.")
        }

        if avgWin > 0, avgLoss != 0 {
            let lossMag = abs(avgLoss)
            let ratio = lossMag / avgWin
            subMetrics.append(
                ScorecardSubMetric(
                    id: "risk.avg_loss_vs_win_context",
                    label: "Average loss vs average win (outcome context)",
                    value: String(format: "%.2f×", ratio),
                    explanation: "Scope-wide outcome context only, not part of the risk score.",
                    sampleSize: trades.count,
                    sampleLabel: "trades"
                )
            )
        }

        if maxDrawdown > 0, trades.count >= 2 {
            subMetrics.append(
                ScorecardSubMetric(
                    id: "risk.max_drawdown_context",
                    label: "Max drawdown in scope (outcome context)",
                    value: String(format: "$%.0f", maxDrawdown),
                    explanation:
                        "Peak-to-trough decline on cumulative P&L, informational; not normalized by account size.",
                    sampleSize: trades.count,
                    sampleLabel: "trades"
                )
            )
        }

        if rrTarget.pairedCount >= 2, let attainment = rrTarget.avgTargetAttainmentRatio {
            let attainmentDouble = NSDecimalNumber(decimal: attainment).doubleValue
            subMetrics.append(
                ScorecardSubMetric(
                    id: "risk.target_attainment_context",
                    label: "Average max R vs planned R (outcome context)",
                    value: ScorecardReliabilitySupport.formatPercent(attainmentDouble),
                    explanation: rrTarget.sampleSummary
                        ?? "Price excursion relative to planned R, outcome context only, not scored in Phase 1.",
                    sampleSize: rrTarget.pairedCount,
                    sampleLabel: "paired trades"
                )
            )
        }

        dataGaps.append(
            "Risk category is insights and coverage only in Phase 1, no numerical score until a defensible behavioral metric exists."
        )

        let coveragePercent = ScorecardReliabilitySupport.clampScore(
            (rrCoverage + realizedCoverage + maxRrCoverage) / 3 * 100
        )
        let reliability = ScorecardReliabilitySupport.resolve(
            sampleSize: max(withPlannedRr.count, withRealizedRr.count, trades.count)
        )

        return ScorecardCategoryResult(
            id: .risk,
            title: "Risk Management",
            weight: weight,
            score: nil,
            coveragePercent: coveragePercent,
            reliability: reliability,
            eligible: false,
            subMetrics: subMetrics,
            strengths: strengths,
            weaknesses: weaknesses,
            dataGaps: dataGaps
        )
    }
}
