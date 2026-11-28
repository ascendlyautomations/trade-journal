import CryptoKit
import Foundation

/// Builds structured coach facts from Phase 4 analytics, never raw trades or check-in notes.
nonisolated enum PsychologyCoachFactsBuilder {
    static func build(
        report: PsychologyAnalyticsReport,
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        now: Date = Date(),
        preferences: PreferenceRuleContext? = nil,
        scope: PsychologyCoachScopeFacts? = nil
    ) -> PsychologyCoachFacts {
        let enriched = TraderPsychologyAnalyticsEngine.enrich(trades: trades, checkIns: checkIns)
        let trends = PsychologyTrendAnalyzer.analyze(trades: trades, checkIns: checkIns)
        let comparison = PsychologyComparisonBuilder.build(enriched: enriched, preferences: preferences)

        let topInsights = report.dashboardCards.map { factInsight(from: $0, sections: report.sections) }
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
            Dictionary(combined.map { ($0.id, factInsight(from: $0, sections: report.sections)) }, uniquingKeysWith: { first, _ in first })
                .values
        )

        let comparisons = report.sections.map { section in
            let card = report.dashboardCards.first { $0.id == section.id }
            return comparisonFact(from: section, card: card)
        }

        let baseline = PsychologyCoachFactMetric(
            tradeCount: report.baseline.tradeCount,
            winRate: decimalDouble(report.baseline.winRate),
            expectancy: decimalDouble(report.baseline.expectancy),
            averagePnL: decimalDouble(report.baseline.averagePnL),
            reliability: report.baseline.reliability.rawValue
        )

        let gaps = dataGaps(report: report, enriched: enriched)
        let hasMinimum = report.baseline.tradeCount >= 5
        let deterministic = PsychologyCoachDeterministicCoach.buildSummary(from: baseFactsForDeterministic(
            baseline: baseline,
            topInsights: topInsights,
            guardrails: comparison.guardrails,
            gaps: gaps,
            hasMinimum: hasMinimum
        ))

        var facts = PsychologyCoachFacts(
            generatedAt: now,
            factsHash: "",
            scope: scope ?? PsychologyCoachScopeFacts(label: "All accounts", fingerprint: "default"),
            reportMeta: PsychologyCoachReportMetaFacts(
                enrichedTradeCount: report.enrichedTradeCount,
                checkInMatchedTradeCount: report.checkInMatchedTradeCount,
                matchedDayCount: report.matchedDayCount
            ),
            baseline: baseline,
            comparisons: comparisons,
            topInsights: topInsights,
            combinedPatterns: combinedFacts,
            trends: trends,
            checkInAggregates: buildCheckInAggregates(trades: trades, checkIns: checkIns, matchedDayCount: report.matchedDayCount),
            tradingRulesCompliance: buildTradingRulesFacts(trades: trades, preferences: preferences),
            deterministicCoach: PsychologyCoachDeterministicFacts(
                overview: deterministic.overview,
                doingWell: deterministic.doingWell,
                watchItems: deterministic.watchItems,
                recommendations: deterministic.recommendations
            ),
            guardrailFacts: comparison.guardrails,
            dataGaps: gaps,
            hasMinimumData: hasMinimum
        )
        facts.factsHash = hash(facts)
        return facts
    }

    private static func baseFactsForDeterministic(
        baseline: PsychologyCoachFactMetric,
        topInsights: [PsychologyCoachFactInsight],
        guardrails: PsychologyCoachGuardrailFacts,
        gaps: [String],
        hasMinimum: Bool
    ) -> PsychologyCoachFacts {
        PsychologyCoachFacts(
            generatedAt: Date(),
            factsHash: "",
            scope: PsychologyCoachScopeFacts(label: "", fingerprint: ""),
            reportMeta: .init(enrichedTradeCount: 0, checkInMatchedTradeCount: 0, matchedDayCount: 0),
            baseline: baseline,
            comparisons: [],
            topInsights: topInsights,
            combinedPatterns: [],
            trends: [],
            checkInAggregates: .init(matchedDayCount: 0, averageSleepHours: nil, averageStress: nil, averageMood: nil, averageConfidence: nil, averageEnergy: nil, averageFocus: nil),
            tradingRulesCompliance: nil,
            deterministicCoach: .init(overview: "", doingWell: [], watchItems: [], recommendations: []),
            guardrailFacts: guardrails,
            dataGaps: gaps,
            hasMinimumData: hasMinimum
        )
    }

    static func hash(_ facts: PsychologyCoachFacts) -> String {
        var copy = facts
        copy.factsHash = ""
        copy.generatedAt = Date(timeIntervalSince1970: 0)
        guard let data = try? JSONEncoder.psychologyCoach.encode(copy) else { return UUID().uuidString }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func factInsight(
        from card: PsychologyInsightCard,
        sections: [PsychologyAnalyticsSection]
    ) -> PsychologyCoachFactInsight {
        let section = sections.first { $0.id == card.id }
        let leader = section?.groups.first(where: \.highlight) ?? section?.groups.first
        return PsychologyCoachFactInsight(
            id: card.id,
            category: card.category.rawValue,
            headline: card.headline,
            detail: card.detail,
            sampleSize: card.sampleSize,
            reliability: card.reliability.rawValue,
            expectancy: decimalDouble(leader?.metrics.expectancy),
            winRate: decimalDouble(leader?.metrics.winRate),
            averagePnL: decimalDouble(leader?.metrics.averagePnL)
        )
    }

    private static func comparisonFact(
        from section: PsychologyAnalyticsSection,
        card: PsychologyInsightCard?
    ) -> PsychologyCoachComparisonFact {
        let left = section.groups.first
        let right = section.groups.dropFirst().first
        let detail = card?.detail ?? section.footnote ?? ""
        return PsychologyCoachComparisonFact(
            id: section.id,
            category: card?.category.rawValue ?? section.id,
            title: section.title,
            headline: card?.headline ?? section.title,
            suggestion: detail,
            sampleLine: section.footnote ?? detail,
            reliability: (left?.metrics.reliability ?? .insufficient).rawValue,
            favorableSide: (left?.highlight == true ? left?.label : right?.label) ?? "",
            left: sideFacts(left),
            right: sideFacts(right)
        )
    }

    private static func sideFacts(_ row: PsychologyAnalyticsGroupRow?) -> PsychologyCoachComparisonSide {
        guard let row else {
            return PsychologyCoachComparisonSide(
                label: "",
                sampleLabel: "",
                tradeCount: 0,
                winRate: nil,
                averagePnL: nil,
                expectancy: nil,
                reliability: PsychologySampleReliability.insufficient.rawValue,
                highlight: false
            )
        }
        return PsychologyCoachComparisonSide(
            label: row.label,
            sampleLabel: row.label,
            tradeCount: row.metrics.tradeCount,
            winRate: decimalDouble(row.metrics.winRate),
            averagePnL: decimalDouble(row.metrics.averagePnL),
            expectancy: decimalDouble(row.metrics.expectancy),
            reliability: row.metrics.reliability.rawValue,
            highlight: row.highlight
        )
    }

    private static func buildCheckInAggregates(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        matchedDayCount: Int
    ) -> PsychologyCoachCheckInAggregates {
        let days = EarlyPsychologyInsightsBuilder.buildMatchedTradingDays(trades: trades, checkIns: checkIns)
        guard !days.isEmpty else {
            return PsychologyCoachCheckInAggregates(
                matchedDayCount: matchedDayCount,
                averageSleepHours: nil,
                averageStress: nil,
                averageMood: nil,
                averageConfidence: nil,
                averageEnergy: nil,
                averageFocus: nil
            )
        }
        func average(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        let sleep = days.compactMap(\.checkIn.sleepHours).map(decimalDouble)
        let stress = days.compactMap(\.checkIn.stressLevel).map { Double($0) }
        let mood = days.compactMap(\.checkIn.morningRating).map { Double($0) }
        let sleepQuality = days.compactMap(\.checkIn.sleepQuality).map { Double($0) }
        let energy = days.compactMap(\.checkIn.energyLevel).map { Double($0) }
        let focus = days.compactMap(\.checkIn.focusLevel).map { Double($0) }
        return PsychologyCoachCheckInAggregates(
            matchedDayCount: matchedDayCount,
            averageSleepHours: average(sleep),
            averageStress: average(stress),
            averageMood: average(mood),
            averageConfidence: average(sleepQuality),
            averageEnergy: average(energy),
            averageFocus: average(focus)
        )
    }

    private static func buildTradingRulesFacts(
        trades: [Trade],
        preferences: PreferenceRuleContext?
    ) -> PsychologyCoachTradingRulesFacts? {
        guard let preferences else { return nil }
        let result = TradingRulesComplianceAnalytics.build(trades: trades, context: preferences)
        let score = result.score
        let impacts = result.impacts
            .filter(\.sufficientSample)
            .sorted { $0.violated.priced > $1.violated.priced }
            .prefix(5)
            .map { row in
                PsychologyCoachRuleViolationFact(
                    ruleId: row.ruleID.rawValue,
                    ruleLabel: row.ruleLabel,
                    violationCount: row.violated.priced,
                    followedWinRate: row.followed.winRateFraction,
                    violatedWinRate: row.violated.winRateFraction
                )
            }
        return PsychologyCoachTradingRulesFacts(
            adherencePercent: score.adherencePercent,
            evaluated: score.evaluated,
            followed: score.followed,
            violated: score.violated,
            topViolationRules: Array(impacts)
        )
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

    private static func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private static func decimalDouble(_ value: Decimal?) -> Double? {
        guard let value else { return nil }
        return decimalDouble(value)
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