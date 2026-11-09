import Foundation

nonisolated enum TradingScorecardBuilder {
    struct Highlights: Sendable, Hashable {
        var strengths: [String]
        var weaknesses: [String]
    }

    static func build(input: ScorecardBuildInput, domainTrades: [Trade]) -> ScorecardResult {
        let trades = input.trades
        let postLoss = input.analytics.postTripleLossWinRate ?? ScorecardTradeMapper.postTripleLossWinRate(trades: trades)

        let categories: [ScorecardCategoryResult] = [
            ScorecardConsistency.score(
                trades: trades,
                tradingDayCount: input.analytics.periodTradingDayCount,
                postTripleLossWinRate: postLoss
            ),
            ScorecardRisk.score(
                trades: trades,
                maxDrawdown: input.analytics.maxDrawdown,
                avgWin: input.analytics.avgWin,
                avgLoss: input.analytics.avgLoss,
                rrTarget: input.analytics.rrTargetAnalysis
            ),
            ScorecardDiscipline.score(trades: trades),
            ScorecardPsychology.score(
                trades: trades,
                checkIns: input.checkIns,
                domainTrades: domainTrades
            ),
        ]

        let overall = computeOverall(
            categories: categories,
            tradeCount: input.analytics.totalTrades,
            tradingDayCount: input.analytics.periodTradingDayCount
        )

        return ScorecardResult(
            scopeLabel: input.scopeLabel,
            generatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            overall: overall,
            categories: categories
        )
    }

    static func collectTopStrengthsAndWeaknesses(result: ScorecardResult, limit: Int = 3) -> Highlights {
        var strengths: [String] = []
        var weaknesses: [String] = []
        for category in result.categories {
            strengths.append(contentsOf: category.strengths)
            weaknesses.append(contentsOf: category.weaknesses)
        }
        return Highlights(
            strengths: Array(strengths.prefix(limit)),
            weaknesses: Array(weaknesses.prefix(limit))
        )
    }

    private static func computeOverall(
        categories: [ScorecardCategoryResult],
        tradeCount: Int,
        tradingDayCount: Int
    ) -> ScorecardOverallResult {
        let scored = categories.filter {
            $0.score != nil && $0.eligible && $0.reliability != .insufficient
        }

        func baseBuilding(_ statusMessage: String, status: ScorecardOverallStatus = .building) -> ScorecardOverallResult {
            ScorecardOverallResult(
                score: nil,
                status: tradeCount > 0 ? status : .unavailable,
                statusMessage: statusMessage,
                coveragePercent: 0,
                reliability: ScorecardReliabilitySupport.resolve(sampleSize: tradeCount),
                tradeCount: tradeCount,
                tradingDayCount: tradingDayCount,
                contributions: [],
                nominalWeightIncluded: 0
            )
        }

        if tradeCount < ScorecardConstants.minTradesOverall
            || tradingDayCount < ScorecardConstants.minTradingDaysOverall
        {
            var parts: [String] = []
            if tradeCount < ScorecardConstants.minTradesOverall {
                parts.append("\(tradeCount)/\(ScorecardConstants.minTradesOverall) trades in scope")
            }
            if tradingDayCount < ScorecardConstants.minTradingDaysOverall {
                parts.append("\(tradingDayCount)/\(ScorecardConstants.minTradingDaysOverall) trading days")
            }
            return baseBuilding("Building your score, \(parts.joined(separator: " · "))")
        }

        if scored.isEmpty {
            return baseBuilding(
                "Building your score, tag plan adherence after losses and on more trades to unlock category scores. Category breakdowns below show coverage and insights."
            )
        }

        var nominalIncluded = 0.0
        for category in scored {
            nominalIncluded += ScorecardConstants.categoryWeights[category.id] ?? 0
        }

        var weightSum = 0.0
        var weighted = 0.0
        var contributions: [ScorecardOverallContribution] = []

        for category in scored {
            let w = ScorecardConstants.categoryWeights[category.id] ?? 0
            weightSum += w
            weighted += w * Double(category.score ?? 0)
        }

        for category in scored {
            let w = ScorecardConstants.categoryWeights[category.id] ?? 0
            contributions.append(
                ScorecardOverallContribution(
                    id: category.id,
                    title: category.title,
                    score: category.score ?? 0,
                    nominalWeight: w,
                    effectiveWeight: w / weightSum
                )
            )
        }

        let score = Int((weighted / weightSum).rounded())
        let coveragePercent = Int(
            (Double(scored.reduce(0) { $0 + $1.coveragePercent }) / Double(scored.count)).rounded()
        )
        var reliability: ScorecardReliability = .strong
        for category in scored {
            reliability = ScorecardReliabilitySupport.minReliability(reliability, category.reliability)
        }

        var statusMessage = "Overall trading score for the current dashboard scope."
        if nominalIncluded < 0.999 {
            let pct = Int((nominalIncluded * 100).rounded())
            statusMessage +=
                " Based on \(scored.count) of 4 categories (\(pct)% of nominal weight), Psychology and Risk are insights/coverage only in Phase 1."
        }

        return ScorecardOverallResult(
            score: score,
            status: .ready,
            statusMessage: statusMessage,
            coveragePercent: coveragePercent,
            reliability: reliability,
            tradeCount: tradeCount,
            tradingDayCount: tradingDayCount,
            contributions: contributions,
            nominalWeightIncluded: nominalIncluded
        )
    }
}
