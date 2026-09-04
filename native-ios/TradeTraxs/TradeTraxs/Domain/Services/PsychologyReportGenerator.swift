import CryptoKit
import Foundation

/// Deterministic psychology report builder — reuses Phase 4 analytics engine.
nonisolated enum PsychologyReportGenerator {
    static func generateAll(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        now: Date = Date()
    ) -> PsychologyReportsSnapshot {
        let catalog = PsychologyReportPeriods.availableCatalog(trades: trades, now: now)
        var reports: [ReportID: PsychologyReport] = [:]
        for ref in catalog {
            let report = generate(
                periodRef: ref,
                trades: trades,
                checkIns: checkIns,
                now: now
            )
            reports[report.id] = report
        }
        return PsychologyReportsSnapshot(
            reports: reports,
            computedAt: now.timeIntervalSince1970 * 1000,
            catalogPeriods: catalog
        )
    }

    static func generate(
        periodRef: PsychologyReportPeriodRef,
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        now: Date = Date()
    ) -> PsychologyReport {
        let bounds = PsychologyReportPeriods.bounds(for: periodRef, now: now)
        let periodTrades = filterTrades(trades, start: bounds.start, end: bounds.end)
        let periodCheckIns = filterCheckIns(checkIns, start: bounds.start, end: bounds.end)

        let analytics = TraderPsychologyAnalyticsEngine.buildReport(
            trades: periodTrades,
            checkIns: periodCheckIns,
            now: now
        )
        let facts = PsychologyCoachFactsBuilder.build(
            report: analytics,
            trades: periodTrades,
            checkIns: periodCheckIns,
            now: now
        )
        let summary = PsychologyCoachDeterministicCoach.buildSummary(from: facts)

        let checkInSummary = buildCheckInSummary(periodCheckIns)
        let tradingPsych = buildTradingPsychology(periodTrades)
        let behavior = buildBehavior(periodTrades: periodTrades, checkIns: periodCheckIns, analytics: analytics)
        let comparisons = buildComparisons(
            periodRef: periodRef,
            trades: trades,
            checkIns: checkIns,
            now: now
        )
        let sections = buildSections(
            template: periodRef.template,
            analytics: analytics,
            checkInSummary: checkInSummary,
            tradingPsych: tradingPsych,
            behavior: behavior,
            facts: facts
        )

        return PsychologyReport(
            periodRef: periodRef,
            title: periodRef.template.catalogTitle,
            dateRangeLabel: bounds.dateRangeLabel,
            periodStartIso: iso(bounds.start),
            periodEndIso: iso(bounds.end),
            generatedAt: now.timeIntervalSince1970 * 1000,
            factsHash: facts.factsHash,
            checkInSummary: checkInSummary,
            tradingPsychology: tradingPsych,
            behavior: behavior,
            performance: analytics.baseline,
            comparisons: comparisons,
            doingWell: summary.doingWell,
            watchItems: summary.watchItems,
            sections: sections
        )
    }

    // MARK: - Filters

    private static func filterTrades(_ trades: [Trade], start: Date, end: Date) -> [Trade] {
        trades.filter { $0.entryAt >= start && $0.entryAt <= end }
    }

    private static func filterCheckIns(_ checkIns: [TraderDailyCheckIn], start: Date, end: Date) -> [TraderDailyCheckIn] {
        let startKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: start)
        let endKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: end)
        return checkIns.filter { $0.checkInDate >= startKey && $0.checkInDate <= endKey }
    }

    // MARK: - Summaries

    private static func buildCheckInSummary(_ checkIns: [TraderDailyCheckIn]) -> PsychologyReportCheckInSummary {
        func avg(_ values: [Int]) -> Double? {
            guard !values.isEmpty else { return nil }
            return Double(values.reduce(0, +)) / Double(values.count)
        }
        func avgDecimal(_ values: [Decimal]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sum = values.reduce(0, +)
            return NSDecimalNumber(decimal: sum / Decimal(values.count)).doubleValue
        }

        return PsychologyReportCheckInSummary(
            checkInCount: checkIns.count,
            averageSleepHours: avgDecimal(checkIns.compactMap(\.sleepHours)),
            averageSleepQuality: avg(checkIns.compactMap(\.sleepQuality)),
            averageMorningRating: avg(checkIns.compactMap(\.morningRating)),
            averageStress: avg(checkIns.compactMap(\.stressLevel)),
            averageEnergy: avg(checkIns.compactMap(\.energyLevel)),
            averageFocus: avg(checkIns.compactMap(\.focusLevel))
        )
    }

    private static func buildTradingPsychology(_ trades: [Trade]) -> PsychologyReportTradingPsychology {
        let taggedPlan = trades.filter { $0.followedPlan != nil }
        let followedRate: Double? = taggedPlan.isEmpty ? nil : Double(taggedPlan.filter { $0.followedPlan == true }.count) / Double(taggedPlan.count)

        let convictions = trades.compactMap(\.confidence).filter { $0 > 0 }
        let avgConviction: Double? = convictions.isEmpty ? nil : Double(convictions.reduce(0, +)) / Double(convictions.count)

        let emotions = trades.compactMap { $0.emotion?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let emotionCounts = Dictionary(grouping: emotions, by: { $0 }).mapValues(\.count)
        let topEmotion = emotionCounts.max(by: { $0.value < $1.value })?.key

        func emotionCount(_ name: String) -> Int {
            emotions.filter { $0.caseInsensitiveCompare(name) == .orderedSame }.count
        }

        let execRatings = trades.compactMap(\.executionRating).filter { $0 > 0 }
        let avgExec: Double? = execRatings.isEmpty ? nil : Double(execRatings.reduce(0, +)) / Double(execRatings.count)

        return PsychologyReportTradingPsychology(
            followedPlanRate: followedRate,
            averageConviction: avgConviction,
            mostCommonEmotion: topEmotion,
            fomoTradeCount: emotionCount("FOMO"),
            frustratedTradeCount: emotionCount("Frustrated"),
            averageExecutionRating: avgExec
        )
    }

    private static func buildBehavior(
        periodTrades: [Trade],
        checkIns: [TraderDailyCheckIn],
        analytics: PsychologyAnalyticsReport
    ) -> PsychologyReportBehaviorSummary {
        let enriched = TraderPsychologyAnalyticsEngine.enrich(trades: periodTrades, checkIns: checkIns)
        let dayCounts = Dictionary(grouping: enriched) {
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0.trade)
        }.mapValues(\.count)
        let avgTradesPerDay: Double? = dayCounts.isEmpty ? nil : Double(dayCounts.values.reduce(0, +)) / Double(dayCounts.count)

        let afterTwo = enriched.filter { $0.consecutiveLossesBefore >= 2 }
        let afterTwoMetrics = TraderPsychologyAnalyticsEngine.metrics(for: afterTwo.map(\.trade))

        let grouped = Dictionary(grouping: enriched) {
            TraderPsychologyAnalyticsEngine.TradeSequenceBucket.resolve($0.tradeNumberInDay)
        }
        let early = (grouped[.first] ?? []) + (grouped[.second] ?? []) + (grouped[.third] ?? [])
        let late = grouped[.fifthPlus] ?? []
        let earlyM = TraderPsychologyAnalyticsEngine.metrics(for: early.map(\.trade))
        let lateM = TraderPsychologyAnalyticsEngine.metrics(for: late.map(\.trade))

        return PsychologyReportBehaviorSummary(
            averageTradesPerDay: avgTradesPerDay,
            afterTwoLossesWinRate: afterTwoMetrics.winRate.map { NSDecimalNumber(decimal: $0).doubleValue },
            afterTwoLossesBaselineWinRate: analytics.baseline.winRate.map { NSDecimalNumber(decimal: $0).doubleValue },
            earlyTradeAvgPnL: earlyM.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue },
            lateTradeAvgPnL: lateM.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue }
        )
    }

    private static func buildComparisons(
        periodRef: PsychologyReportPeriodRef,
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        now: Date
    ) -> [PsychologyReportComparison] {
        guard periodRef.template == .monthly else { return [] }

        let bounds = PsychologyReportPeriods.bounds(for: periodRef, now: now)
        let calendar = Calendar.current
        guard let prevStart = calendar.date(byAdding: .month, value: -1, to: bounds.start),
              let prevEnd = calendar.date(byAdding: .day, value: -1, to: bounds.start)
        else { return [] }

        let currentTrades = filterTrades(trades, start: bounds.start, end: bounds.end)
        let priorTrades = filterTrades(trades, start: prevStart, end: endOfDay(prevEnd, calendar: calendar))
        guard currentTrades.count >= 10, priorTrades.count >= 10 else { return [] }

        let currentCheckIns = filterCheckIns(checkIns, start: bounds.start, end: bounds.end)
        let priorCheckIns = filterCheckIns(checkIns, start: prevStart, end: endOfDay(prevEnd, calendar: calendar))

        var comparisons: [PsychologyReportComparison] = []

        let curPlan = planRate(currentTrades)
        let prevPlan = planRate(priorTrades)
        if let curPlan, let prevPlan, abs(curPlan - prevPlan) >= 0.08 {
            comparisons.append(
                PsychologyReportComparison(
                    headline: curPlan > prevPlan ? "Plan adherence improved" : "Plan adherence slipped",
                    detail: String(format: "This month: %.0f%% vs prior month: %.0f%%", curPlan * 100, prevPlan * 100),
                    reliability: PsychologySampleReliability.developing.rawValue
                )
            )
        }

        let curSleep = avgSleep(currentCheckIns)
        let prevSleep = avgSleep(priorCheckIns)
        if let curSleep, let prevSleep, abs(curSleep - prevSleep) >= 0.5, currentCheckIns.count >= 5, priorCheckIns.count >= 5 {
            comparisons.append(
                PsychologyReportComparison(
                    headline: curSleep > prevSleep ? "Average sleep increased" : "Average sleep decreased",
                    detail: String(format: "This month: %.1fh vs prior: %.1fh", curSleep, prevSleep),
                    reliability: PsychologySampleReliability.developing.rawValue
                )
            )
        }

        let curFocus = avgRating(currentCheckIns.compactMap(\.focusLevel))
        let prevFocus = avgRating(priorCheckIns.compactMap(\.focusLevel))
        if let curFocus, let prevFocus, abs(curFocus - prevFocus) >= 0.4, currentCheckIns.count >= 5 {
            comparisons.append(
                PsychologyReportComparison(
                    headline: curFocus > prevFocus ? "Focus ratings improved" : "Focus ratings declined",
                    detail: String(format: "This month avg: %.1f/5 vs prior: %.1f/5", curFocus, prevFocus),
                    reliability: PsychologySampleReliability.developing.rawValue
                )
            )
        }

        let trends = PsychologyTrendAnalyzer.analyze(trades: currentTrades + priorTrades, checkIns: checkIns)
        for trend in trends.prefix(2) {
            comparisons.append(
                PsychologyReportComparison(
                    headline: trend.headline,
                    detail: trend.detail,
                    reliability: trend.reliability
                )
            )
        }

        return comparisons
    }

    // MARK: - Sections

    private static func buildSections(
        template: PsychologyReportTemplate,
        analytics: PsychologyAnalyticsReport,
        checkInSummary: PsychologyReportCheckInSummary,
        tradingPsych: PsychologyReportTradingPsychology,
        behavior: PsychologyReportBehaviorSummary,
        facts: PsychologyCoachFacts
    ) -> [PsychologyReportSection] {
        var sections: [PsychologyReportSection] = []

        sections.append(performanceSection(analytics.baseline))

        if checkInSummary.checkInCount > 0 {
            sections.append(checkInSection(checkInSummary))
        }

        if tradingPsych.followedPlanRate != nil || tradingPsych.mostCommonEmotion != nil {
            sections.append(disciplineSection(tradingPsych))
            sections.append(emotionSection(tradingPsych))
        }

        if let sleepInsight = facts.topInsights.first(where: { $0.category == "sleep" }) {
            sections.append(
                PsychologyReportSection(
                    id: "sleep",
                    title: "Sleep & Performance",
                    subtitle: nil,
                    bullets: [sleepInsight.headline, sleepInsight.detail],
                    metrics: []
                )
            )
        }

        if let mental = facts.topInsights.first(where: { $0.category == "mentalState" }) {
            sections.append(
                PsychologyReportSection(
                    id: "mentalState",
                    title: "Stress / Focus / Energy",
                    subtitle: nil,
                    bullets: [mental.headline, mental.detail],
                    metrics: mentalStateMetrics(checkInSummary)
                )
            )
        }

        if behavior.afterTwoLossesWinRate != nil {
            sections.append(afterLossesSection(behavior))
        }

        if behavior.earlyTradeAvgPnL != nil || behavior.averageTradesPerDay != nil {
            sections.append(tradeFrequencySection(behavior))
        }

        if !facts.trends.isEmpty {
            sections.append(
                PsychologyReportSection(
                    id: "trends",
                    title: "Trends",
                    subtitle: template == .monthly ? "This period vs prior history" : nil,
                    bullets: facts.trends.map(\.headline),
                    metrics: facts.trends.map {
                        PsychologyReportMetricRow(label: $0.headline, value: $0.detail)
                    }
                )
            )
        }

        let recommendations = PsychologyCoachDeterministicCoach.buildRecommendations(from: facts)
        if !recommendations.isEmpty {
            sections.append(
                PsychologyReportSection(
                    id: "recommendations",
                    title: "What to Watch",
                    subtitle: nil,
                    bullets: recommendations,
                    metrics: []
                )
            )
        }

        return filterSectionsForTemplate(sections, template: template)
    }

    private static func filterSectionsForTemplate(
        _ sections: [PsychologyReportSection],
        template: PsychologyReportTemplate
    ) -> [PsychologyReportSection] {
        switch template {
        case .weekly, .monthly:
            return sections
        case .sleepPerformance:
            return sections.filter { ["performance", "sleep", "checkIn", "trends"].contains($0.id) }
        case .discipline:
            return sections.filter { ["performance", "discipline", "recommendations"].contains($0.id) }
        case .emotions:
            return sections.filter { ["performance", "emotion", "recommendations"].contains($0.id) }
        case .afterLosses:
            return sections.filter { ["performance", "afterLosses", "recommendations"].contains($0.id) }
        case .mentalState:
            return sections.filter { ["performance", "checkIn", "mentalState"].contains($0.id) }
        case .tradeFrequency:
            return sections.filter { ["performance", "tradeFrequency", "recommendations"].contains($0.id) }
        }
    }

    private static func performanceSection(_ baseline: PsychologyGroupMetrics) -> PsychologyReportSection {
        PsychologyReportSection(
            id: "performance",
            title: "Performance Overview",
            subtitle: "\(baseline.tradeCount) trades in period",
            bullets: [],
            metrics: [
                PsychologyReportMetricRow(label: "P&L", value: TraderPsychologyAnalyticsEngine.money(baseline.totalPnL)),
                PsychologyReportMetricRow(label: "Win Rate", value: TraderPsychologyAnalyticsEngine.formatWinRate(baseline.winRate)),
                PsychologyReportMetricRow(label: "Expectancy", value: TraderPsychologyAnalyticsEngine.money(baseline.expectancy ?? 0)),
                PsychologyReportMetricRow(label: "Avg Trade", value: TraderPsychologyAnalyticsEngine.money(baseline.averagePnL ?? 0)),
                PsychologyReportMetricRow(
                    label: "Profit Factor",
                    value: baseline.profitFactor.map { String(format: "%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "—"
                ),
            ]
        )
    }

    private static func checkInSection(_ summary: PsychologyReportCheckInSummary) -> PsychologyReportSection {
        var metrics: [PsychologyReportMetricRow] = [
            PsychologyReportMetricRow(label: "Check-ins", value: "\(summary.checkInCount)"),
        ]
        if let v = summary.averageSleepHours {
            metrics.append(PsychologyReportMetricRow(label: "Avg Sleep", value: String(format: "%.1fh", v)))
        }
        if let v = summary.averageFocus {
            metrics.append(PsychologyReportMetricRow(label: "Avg Focus", value: String(format: "%.1f/5", v)))
        }
        if let v = summary.averageStress {
            metrics.append(
                PsychologyReportMetricRow(
                    label: "Avg Stress",
                    value: TraderDailyCheckInStressScale.averageDisplayText(for: v)
                )
            )
        }
        return PsychologyReportSection(
            id: "checkIn",
            title: "Daily Check-In Trends",
            subtitle: nil,
            bullets: [],
            metrics: metrics
        )
    }

    private static func disciplineSection(_ psych: PsychologyReportTradingPsychology) -> PsychologyReportSection {
        var metrics: [PsychologyReportMetricRow] = []
        if let rate = psych.followedPlanRate {
            metrics.append(PsychologyReportMetricRow(label: "Followed Plan", value: String(format: "%.0f%%", rate * 100)))
        }
        if let conv = psych.averageConviction {
            metrics.append(PsychologyReportMetricRow(label: "Avg Conviction", value: String(format: "%.1f/5", conv)))
        }
        if let exec = psych.averageExecutionRating {
            metrics.append(PsychologyReportMetricRow(label: "Avg Execution", value: String(format: "%.1f/5", exec)))
        }
        return PsychologyReportSection(id: "discipline", title: "Discipline", subtitle: nil, bullets: [], metrics: metrics)
    }

    private static func emotionSection(_ psych: PsychologyReportTradingPsychology) -> PsychologyReportSection {
        var metrics: [PsychologyReportMetricRow] = []
        if let emotion = psych.mostCommonEmotion {
            metrics.append(PsychologyReportMetricRow(label: "Most Common", value: emotion))
        }
        if psych.fomoTradeCount > 0 {
            metrics.append(PsychologyReportMetricRow(label: "FOMO Trades", value: "\(psych.fomoTradeCount)"))
        }
        if psych.frustratedTradeCount > 0 {
            metrics.append(PsychologyReportMetricRow(label: "Frustrated Trades", value: "\(psych.frustratedTradeCount)"))
        }
        return PsychologyReportSection(id: "emotion", title: "Emotions", subtitle: nil, bullets: [], metrics: metrics)
    }

    private static func mentalStateMetrics(_ summary: PsychologyReportCheckInSummary) -> [PsychologyReportMetricRow] {
        var rows: [PsychologyReportMetricRow] = []
        if let v = summary.averageEnergy {
            rows.append(PsychologyReportMetricRow(label: "Avg Energy", value: String(format: "%.1f/5", v)))
        }
        if let v = summary.averageMorningRating {
            rows.append(PsychologyReportMetricRow(label: "Avg Morning", value: String(format: "%.1f/5", v)))
        }
        return rows
    }

    private static func afterLossesSection(_ behavior: PsychologyReportBehaviorSummary) -> PsychologyReportSection {
        var bullets: [String] = []
        if let after = behavior.afterTwoLossesWinRate, let base = behavior.afterTwoLossesBaselineWinRate {
            bullets.append(String(format: "Win rate after 2+ losses: %.0f%% vs %.0f%% baseline", after * 100, base * 100))
        }
        return PsychologyReportSection(id: "afterLosses", title: "After Losses", subtitle: nil, bullets: bullets, metrics: [])
    }

    private static func tradeFrequencySection(_ behavior: PsychologyReportBehaviorSummary) -> PsychologyReportSection {
        var metrics: [PsychologyReportMetricRow] = []
        if let avg = behavior.averageTradesPerDay {
            metrics.append(PsychologyReportMetricRow(label: "Trades/Day", value: String(format: "%.1f", avg)))
        }
        if let early = behavior.earlyTradeAvgPnL, let late = behavior.lateTradeAvgPnL {
            metrics.append(PsychologyReportMetricRow(label: "Trades 1–3 Avg", value: String(format: "$%.0f", early)))
            metrics.append(PsychologyReportMetricRow(label: "Trade #5+ Avg", value: String(format: "$%.0f", late)))
        }
        return PsychologyReportSection(id: "tradeFrequency", title: "Trade Frequency", subtitle: nil, bullets: [], metrics: metrics)
    }

    // MARK: - Helpers

    private static func planRate(_ trades: [Trade]) -> Double? {
        let tagged = trades.filter { $0.followedPlan != nil }
        guard !tagged.isEmpty else { return nil }
        return Double(tagged.filter { $0.followedPlan == true }.count) / Double(tagged.count)
    }

    private static func avgSleep(_ checkIns: [TraderDailyCheckIn]) -> Double? {
        let hours = checkIns.compactMap(\.sleepHours)
        guard !hours.isEmpty else { return nil }
        let sum = hours.reduce(0, +)
        return NSDecimalNumber(decimal: sum / Decimal(hours.count)).doubleValue
    }

    private static func avgRating(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return date }
        return next.addingTimeInterval(-0.001)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601.string(from: date)
    }
}
