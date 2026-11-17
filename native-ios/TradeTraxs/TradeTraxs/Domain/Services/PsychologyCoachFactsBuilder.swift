import CryptoKit
import Foundation

/// Builds structured coach facts from Phase 4 analytics — never raw trades or check-in notes.
nonisolated enum PsychologyCoachFactsBuilder {
    static func build(
        report: PsychologyAnalyticsReport,
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        now: Date = Date(),
        preferences: PreferenceRuleContext? = nil
    ) -> PsychologyCoachFacts {
        let enriched = TraderPsychologyAnalyticsEngine.enrich(trades: trades, checkIns: checkIns)
        let trends = PsychologyTrendAnalyzer.analyze(trades: trades, checkIns: checkIns)
        let guardrails = buildGuardrailFacts(
            enriched: enriched,
            baseline: report.baseline,
            preferences: preferences
        )

        let topInsights = report.dashboardCards.map { factInsight(from: $0) }
        let combined = report.dashboardCards
            .filter { $0.category == .combined }
            + report.sections
                .flatMap { section in
                    section.groups.compactMap { row -> PsychologyInsightCard? in
                        guard section.id == "combined" else { return nil }
                        return PsychologyInsightCard(
                            id: row.id,
                            category: .combined,
                            sectionTitle: section.title,
                            headline: row.label,
                            detail: section.subtitle ?? "",
                            sampleSize: row.metrics.tradeCount,
                            reliability: row.metrics.reliability,
                            rankingScore: 0
                        )
                    }
                }
        let combinedFacts = Array(
            Dictionary(combined.map { ($0.id, factInsight(from: $0)) }, uniquingKeysWith: { first, _ in first })
                .values
        )

        let baseline = PsychologyCoachFactMetric(
            tradeCount: report.baseline.tradeCount,
            winRate: decimalDouble(report.baseline.winRate),
            expectancy: decimalDouble(report.baseline.expectancy),
            averagePnL: decimalDouble(report.baseline.averagePnL),
            reliability: report.baseline.reliability.rawValue
        )

        let gaps = dataGaps(report: report, enriched: enriched)
        let hasMinimum = report.baseline.tradeCount >= 5

        var facts = PsychologyCoachFacts(
            generatedAt: now,
            factsHash: "",
            baseline: baseline,
            topInsights: topInsights,
            combinedPatterns: combinedFacts,
            trends: trends,
            guardrailFacts: guardrails,
            dataGaps: gaps,
            hasMinimumData: hasMinimum
        )
        facts.factsHash = hash(facts)
        return facts
    }

    static func hash(_ facts: PsychologyCoachFacts) -> String {
        var copy = facts
        copy.factsHash = ""
        copy.generatedAt = Date(timeIntervalSince1970: 0)
        guard let data = try? JSONEncoder.psychologyCoach.encode(copy) else { return UUID().uuidString }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func factInsight(from card: PsychologyInsightCard) -> PsychologyCoachFactInsight {
        PsychologyCoachFactInsight(
            id: card.id,
            category: card.category.rawValue,
            headline: card.headline,
            detail: card.detail,
            sampleSize: card.sampleSize,
            reliability: card.reliability.rawValue,
            expectancy: nil,
            winRate: nil,
            averagePnL: nil
        )
    }

    private static func buildGuardrailFacts(
        enriched: [PsychologyEnrichedTrade],
        baseline: PsychologyGroupMetrics,
        preferences: PreferenceRuleContext? = nil
    ) -> PsychologyCoachGuardrailFacts {
        _ = baseline
        return PsychologyComparisonBuilder.build(enriched: enriched, preferences: preferences).guardrails
    }

    static func dataGapMessages(
        report: PsychologyAnalyticsReport,
        trades: [Trade],
        checkIns: [TraderDailyCheckIn]
    ) -> [String] {
        let enriched = TraderPsychologyAnalyticsEngine.enrich(trades: trades, checkIns: checkIns)
        return dataGaps(report: report, enriched: enriched)
    }

    private static func dataGaps(
        report: PsychologyAnalyticsReport,
        enriched: [PsychologyEnrichedTrade]
    ) -> [String] {
        var gaps: [String] = []
        if report.baseline.tradeCount < 5 {
            gaps.append("Log at least 5 trades to unlock personalized coaching.")
        }
        if report.matchedDayCount < 5 {
            gaps.append("Complete daily check-ins on trading days to unlock sleep and mental-state patterns.")
        }
        let withConviction = enriched.filter { ($0.trade.confidence ?? 0) > 0 }.count
        if withConviction < 5 {
            gaps.append("Add conviction ratings on trades to compare high vs low conviction performance.")
        }
        let withEmotion = enriched.filter { $0.trade.emotion?.isEmpty == false }.count
        if withEmotion < 5 {
            gaps.append("Tag emotions before entry to see which states correlate with weaker results.")
        }
        return gaps
    }

    private static func decimalDouble(_ value: Decimal?) -> Double? {
        guard let value else { return nil }
        return NSDecimalNumber(decimal: value).doubleValue
    }
}

private nonisolated extension JSONEncoder {
    static let psychologyCoach: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
