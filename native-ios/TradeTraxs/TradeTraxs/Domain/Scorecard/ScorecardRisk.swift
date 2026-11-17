import Foundation

/// Risk is not scored. Planned R and max R feed the scorecard insight when the
/// average favorable excursion falls short of the target.
nonisolated enum ScorecardRisk {
    static func score(
        trades: [ScorecardTrade],
        maxDrawdown: Double,
        avgWin: Double,
        avgLoss: Double,
        rrTarget: DashboardRrTargetAnalysis
    ) -> ScorecardCategoryResult {
        _ = maxDrawdown
        _ = avgWin
        _ = avgLoss
        _ = rrTarget
        let withPlannedRr = trades.filter { ($0.rr ?? 0) > 0 }
        return ScorecardCategoryResult(
            id: .risk,
            title: "Risk Management",
            weight: ScorecardConstants.categoryWeights[.risk] ?? 0.25,
            score: nil,
            coveragePercent: 0,
            reliability: ScorecardReliabilitySupport.resolve(
                sampleSize: max(withPlannedRr.count, trades.count)
            ),
            eligible: false,
            subMetrics: [],
            strengths: [],
            weaknesses: [],
            dataGaps: []
        )
    }
}
