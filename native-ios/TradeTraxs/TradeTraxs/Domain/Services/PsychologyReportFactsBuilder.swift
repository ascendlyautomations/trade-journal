import Foundation

/// Builds structured facts from a psychology report for AI explanation.
nonisolated enum PsychologyReportFactsBuilder {
    static func build(from report: PsychologyReport) -> PsychologyCoachFacts {
        var topInsights: [PsychologyCoachFactInsight] = []
        topInsights.reserveCapacity(4)

        for (index, headline) in report.doingWell.prefix(2).enumerated() {
            topInsights.append(
                insight(
                    id: "doingWell.\(index)",
                    category: "strength",
                    headline: headline,
                    report: report
                )
            )
        }
        for (index, headline) in report.watchItems.prefix(2).enumerated() {
            topInsights.append(
                insight(
                    id: "watch.\(index)",
                    category: "watch",
                    headline: headline,
                    report: report
                )
            )
        }
        if topInsights.count < 4 {
            for comparison in report.comparisons.prefix(4 - topInsights.count) {
                topInsights.append(
                    PsychologyCoachFactInsight(
                        id: "comparison.\(comparison.headline)",
                        category: "trend",
                        headline: comparison.headline,
                        detail: comparison.detail,
                        sampleSize: report.performance.tradeCount,
                        reliability: comparison.reliability,
                        expectancy: nil,
                        winRate: nil,
                        averagePnL: nil
                    )
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
            topInsights: Array(topInsights.prefix(4)),
            combinedPatterns: [],
            trends: report.comparisons.prefix(2).map {
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

    private static func insight(
        id: String,
        category: String,
        headline: String,
        report: PsychologyReport
    ) -> PsychologyCoachFactInsight {
        PsychologyCoachFactInsight(
            id: id,
            category: category,
            headline: headline,
            detail: report.dateRangeLabel,
            sampleSize: report.performance.tradeCount,
            reliability: report.performance.reliability.rawValue,
            expectancy: report.performance.expectancy.map { NSDecimalNumber(decimal: $0).doubleValue },
            winRate: report.performance.winRate.map { NSDecimalNumber(decimal: $0).doubleValue },
            averagePnL: report.performance.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue }
        )
    }
}
