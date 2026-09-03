import Foundation

/// Builds structured facts from a psychology report for AI explanation.
nonisolated enum PsychologyReportFactsBuilder {
    static func build(from report: PsychologyReport) -> PsychologyCoachFacts {
        let insights = report.sections.flatMap { section -> [PsychologyCoachFactInsight] in
            section.bullets.enumerated().map { index, bullet in
                PsychologyCoachFactInsight(
                    id: "\(section.id).\(index)",
                    category: section.id,
                    headline: bullet,
                    detail: section.subtitle ?? report.dateRangeLabel,
                    sampleSize: report.performance.tradeCount,
                    reliability: report.performance.reliability.rawValue,
                    expectancy: report.performance.expectancy.map { NSDecimalNumber(decimal: $0).doubleValue },
                    winRate: report.performance.winRate.map { NSDecimalNumber(decimal: $0).doubleValue },
                    averagePnL: report.performance.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue }
                )
            }
        }

        return PsychologyCoachFacts(
            generatedAt: Date(timeIntervalSince1970: report.generatedAt / 1000),
            factsHash: report.factsHash,
            baseline: PsychologyCoachFactMetric(
                tradeCount: report.performance.tradeCount,
                winRate: report.performance.winRate.map { NSDecimalNumber(decimal: $0).doubleValue },
                expectancy: report.performance.expectancy.map { NSDecimalNumber(decimal: $0).doubleValue },
                averagePnL: report.performance.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue },
                reliability: report.performance.reliability.rawValue
            ),
            topInsights: Array(insights.prefix(8)),
            combinedPatterns: [],
            trends: report.comparisons.map {
                PsychologyCoachTrendFact(
                    id: $0.headline,
                    headline: $0.headline,
                    detail: $0.detail,
                    recentSampleSize: report.performance.tradeCount,
                    priorSampleSize: 0,
                    reliability: $0.reliability
                )
            },
            guardrailFacts: PsychologyCoachGuardrailFacts(
                consecutiveLossCheckpoint: nil,
                consecutiveLossWinRateAfter: report.behavior.afterTwoLossesWinRate,
                consecutiveLossBaselineWinRate: report.behavior.afterTwoLossesBaselineWinRate,
                lowSleepHoursThreshold: report.checkInSummary.averageSleepHours.map { _ in 6 },
                lowSleepExpectancy: nil,
                maxTradesDaySoftLimit: nil,
                lateTradeAveragePnL: report.behavior.lateTradeAvgPnL,
                earlyTradeAveragePnL: report.behavior.earlyTradeAvgPnL
            ),
            dataGaps: report.performance.tradeCount < 5 ? ["Log more trades in this period."] : [],
            hasMinimumData: report.performance.tradeCount >= 5
        )
    }
}
