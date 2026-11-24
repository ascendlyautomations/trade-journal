import CryptoKit
import Foundation

/// Deterministic psychology report builder, reuses Phase 4 analytics engine.
nonisolated enum PsychologyReportGenerator {
    static func generateAll(
        trades: [Trade],
        checkIns: [TraderDailyCheckIn],
        now: Date = Date(),
        preferences: PreferenceRuleContext? = nil
    ) -> PsychologyReportsSnapshot {
        let catalog = PsychologyReportPeriods.availableCatalog(trades: trades, now: now)
        var reports: [ReportID: PsychologyReport] = [:]
        for ref in catalog {
            let report = generate(
                periodRef: ref,
                trades: trades,
                checkIns: checkIns,
                now: now,
                preferences: preferences
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
        now: Date = Date(),
        preferences: PreferenceRuleContext? = nil
    ) -> PsychologyReport {
        var bounds = PsychologyReportPeriods.bounds(for: periodRef, now: now)
        if periodRef.periodID == PsychologyReportTimePreset.all.rawValue,
           let earliest = trades.map(\.entryAt).min() {
            let calendar = TradingReportPeriods.eastern
            bounds.start = calendar.startOfDay(for: earliest)
            bounds.dateRangeLabel = TradingReportPeriods.dateRangeLabel(
                start: bounds.start,
                end: bounds.end,
                kind: .weekly
            )
        }
        let periodTrades = filterTrades(trades, start: bounds.start, end: bounds.end)
        let periodCheckIns = filterCheckIns(checkIns, start: bounds.start, end: bounds.end)

        let analytics = TraderPsychologyAnalyticsEngine.buildReport(
            trades: periodTrades,
            checkIns: periodCheckIns,
            now: now,
            preferences: preferences
        )
        let facts = PsychologyCoachFactsBuilder.build(
            report: analytics,
            trades: periodTrades,
            checkIns: periodCheckIns,
            now: now,
            preferences: preferences
        )
        let summary = PsychologyCoachDeterministicCoach.buildSummary(from: facts)

        let checkInSummary = buildCheckInSummary(periodCheckIns)
        let tradingPsych = buildTradingPsychology(periodTrades)
        let behavior = buildBehavior(
            periodTrades: periodTrades,
            checkIns: periodCheckIns,
            analytics: analytics,
            preferences: preferences
        )
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

        let planTagged = periodTrades.filter { $0.followedPlan != nil }.count
        let emotionBreakdown = buildEmotionBreakdown(periodTrades)

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
            sections: sections,
            analyticsSections: analytics.sections,
            insightCards: analytics.dashboardCards,
            emotionBreakdown: emotionBreakdown,
            matchedDayCount: analytics.matchedDayCount,
            checkInMatchedTradeCount: analytics.checkInMatchedTradeCount,
            planTaggedTradeCount: planTagged
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
        analytics: PsychologyAnalyticsReport,
        preferences: PreferenceRuleContext? = nil
    ) -> PsychologyReportBehaviorSummary {
        let enriched = TraderPsychologyAnalyticsEngine.enrich(trades: periodTrades, checkIns: checkIns)
        let dayCounts = Dictionary(grouping: enriched) {
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0.trade)
        }.mapValues(\.count)
        let avgTradesPerDay: Double? = dayCounts.isEmpty ? nil : Double(dayCounts.values.reduce(0, +)) / Double(dayCounts.count)

        let rulesAt: (Trade) -> PsychologyRuleSnapshot = { trade in
            PreferenceComplianceEngine.psychologyRules(in: preferences, at: trade.entryAt)
        }
        let pauses = enriched.compactMap { rulesAt($0.trade).consecutiveLossPause }
        let personalPause = !pauses.isEmpty
        let uniquePause = Set(pauses).count == 1 ? pauses.first : nil
        let afterRows = personalPause
            ? enriched.filter {
                guard let pause = rulesAt($0.trade).consecutiveLossPause else { return false }
                return $0.consecutiveLossesBefore >= pause
            }
            : enriched.filter { $0.consecutiveLossesBefore >= 2 }
        let afterMetrics = TraderPsychologyAnalyticsEngine.metrics(for: afterRows.map(\.trade))
        let caps = enriched.compactMap { rulesAt($0.trade).maxTradesPerDay }
        let personalCap = !caps.isEmpty
        let uniqueCap = Set(caps).count == 1 ? caps.first : nil
        let grouped = Dictionary(grouping: enriched) {
            TraderPsychologyAnalyticsEngine.TradeSequenceBucket.resolve($0.tradeNumberInDay)
        }
        let early = personalCap
            ? enriched.filter {
                guard let cap = rulesAt($0.trade).maxTradesPerDay else { return false }
                return $0.tradeNumberInDay <= cap
            }
            : (grouped[.first] ?? []) + (grouped[.second] ?? []) + (grouped[.third] ?? [])
        let late = personalCap
            ? enriched.filter {
                guard let cap = rulesAt($0.trade).maxTradesPerDay else { return false }
                return $0.tradeNumberInDay > cap
            }
            : (grouped[.fifthPlus] ?? [])
        let earlyM = TraderPsychologyAnalyticsEngine.metrics(for: early.map(\.trade))
        let lateM = TraderPsychologyAnalyticsEngine.metrics(for: late.map(\.trade))

        let sequenceReady = early.count >= 8 && late.count >= 8
        let afterReady = afterRows.count >= 8 && enriched.count >= 8
        return PsychologyReportBehaviorSummary(
            averageTradesPerDay: avgTradesPerDay,
            afterTwoLossesWinRate: afterReady ? afterMetrics.winRate.map { NSDecimalNumber(decimal: $0).doubleValue } : nil,
            afterTwoLossesBaselineWinRate: afterReady ? analytics.baseline.winRate.map { NSDecimalNumber(decimal: $0).doubleValue } : nil,
            earlyTradeAvgPnL: sequenceReady ? earlyM.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue } : nil,
            lateTradeAvgPnL: sequenceReady ? lateM.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue } : nil,
            afterLossLabel: personalPause
                ? (uniquePause.map { "Win rate after \($0)+ losses" } ?? "Win rate after your pause")
                : "Win rate after 2+ losses",
            earlyLabel: personalCap
                ? (uniqueCap.map { "Within \($0) trades avg" } ?? "Within your cap avg")
                : "Trades 1–3 Avg",
            lateLabel: personalCap
                ? (uniqueCap.map { "Beyond \($0) trades avg" } ?? "Beyond your cap avg")
                : "Trade #5+ Avg"
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
        let calendar = TradingReportPeriods.eastern
        let currentEndDay = calendar.component(.day, from: bounds.end)
        guard let prevStart = calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: bounds.start))
        else { return [] }
        let priorMonthLength = calendar.range(of: .day, in: .month, for: prevStart)?.count ?? currentEndDay
        let priorDay = min(currentEndDay, priorMonthLength)
        guard let priorEnd = calendar.date(byAdding: .day, value: priorDay - 1, to: calendar.startOfDay(for: prevStart))
        else { return [] }
        let priorIsPartial = priorDay < priorMonthLength
        let currentPartial = bounds.dateRangeLabel.contains("(partial)")
        let currentLabel = currentPartial ? "This month so far" : "This month"
        let priorLabel = priorIsPartial || currentPartial ? "same days last month" : "prior month"

        let currentTrades = filterTrades(trades, start: bounds.start, end: bounds.end)
        let priorTrades = filterTrades(trades, start: prevStart, end: endOfDay(priorEnd, calendar: calendar))
        guard currentTrades.count >= 10, priorTrades.count >= 10 else { return [] }

        let currentCheckIns = filterCheckIns(checkIns, start: bounds.start, end: bounds.end)
        let priorCheckIns = filterCheckIns(checkIns, start: prevStart, end: endOfDay(priorEnd, calendar: calendar))

        var comparisons: [PsychologyReportComparison] = []

        let curPlan = planRate(currentTrades)
        let prevPlan = planRate(priorTrades)
        if let curPlan, let prevPlan, abs(curPlan - prevPlan) >= 0.08 {
            comparisons.append(
                PsychologyReportComparison(
                    headline: curPlan > prevPlan ? "Plan adherence improved" : "Plan adherence slipped",
                    detail: "\(currentLabel): \(NumberDisplay.percent(curPlan * 100, minimumFractionDigits: 0, maximumFractionDigits: 0)) vs \(priorLabel): \(NumberDisplay.percent(prevPlan * 100, minimumFractionDigits: 0, maximumFractionDigits: 0))",
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
                    detail: "\(currentLabel): \(NumberDisplay.hours(curSleep)) vs \(priorLabel): \(NumberDisplay.hours(prevSleep))",
                    reliability: PsychologySampleReliability.developing.rawValue
                )
            )
        }

        let curFocus = avgRating(currentCheckIns.compactMap(\.focusLevel))
        let prevFocus = avgRating(priorCheckIns.compactMap(\.focusLevel))
        if let curFocus, let prevFocus, abs(curFocus - prevFocus) >= 0.4,
           currentCheckIns.count >= 5, priorCheckIns.count >= 5 {
            comparisons.append(
                PsychologyReportComparison(
                    headline: curFocus > prevFocus ? "Focus ratings improved" : "Focus ratings declined",
                    detail: "\(currentLabel) avg: \(NumberDisplay.ratingOutOfFive(curFocus)) vs \(priorLabel): \(NumberDisplay.ratingOutOfFive(prevFocus))",
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
        var metrics: [PsychologyReportMetricRow] = []
        if baseline.averagePnL != nil,
           let pnl = TraderPsychologyAnalyticsEngine.optionalMoney(baseline.totalPnL) {
            metrics.append(PsychologyReportMetricRow(label: "P&L", value: pnl))
        }
        metrics.append(
            PsychologyReportMetricRow(
                label: "Win Rate",
                value: TraderPsychologyAnalyticsEngine.formatWinRate(baseline.winRate)
            )
        )
        if let expectancy = baseline.expectancy,
           let text = TraderPsychologyAnalyticsEngine.optionalMoney(expectancy) {
            metrics.append(PsychologyReportMetricRow(label: "Expectancy", value: text))
        }
        if let average = baseline.averagePnL,
           let text = TraderPsychologyAnalyticsEngine.optionalMoney(average) {
            metrics.append(PsychologyReportMetricRow(label: "Avg Trade", value: text))
        }
        metrics.append(
            PsychologyReportMetricRow(
                label: "Profit Factor",
                value: baseline.profitFactor.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "–"
            )
        )
        return PsychologyReportSection(
            id: "performance",
            title: "Performance Overview",
            subtitle: "\(NumberDisplay.integer(baseline.tradeCount)) trades in period",
            bullets: [],
            metrics: metrics
        )
    }

    private static func checkInSection(_ summary: PsychologyReportCheckInSummary) -> PsychologyReportSection {
        var metrics: [PsychologyReportMetricRow] = [
            PsychologyReportMetricRow(label: "Check-ins", value: NumberDisplay.integer(summary.checkInCount)),
        ]
        if let v = summary.averageSleepHours {
            metrics.append(PsychologyReportMetricRow(label: "Avg Sleep", value: NumberDisplay.hours(v)))
        }
        if let v = summary.averageFocus {
            metrics.append(PsychologyReportMetricRow(label: "Avg Focus", value: NumberDisplay.ratingOutOfFive(v)))
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
            metrics.append(PsychologyReportMetricRow(label: "Followed Plan", value: NumberDisplay.percent(rate * 100, minimumFractionDigits: 0, maximumFractionDigits: 0)))
        }
        if let conv = psych.averageConviction {
            metrics.append(PsychologyReportMetricRow(label: "Avg Conviction", value: NumberDisplay.ratingOutOfFive(conv)))
        }
        if let exec = psych.averageExecutionRating {
            metrics.append(PsychologyReportMetricRow(label: "Avg Execution", value: NumberDisplay.ratingOutOfFive(exec)))
        }
        return PsychologyReportSection(id: "discipline", title: "Discipline", subtitle: nil, bullets: [], metrics: metrics)
    }

    private static func emotionSection(_ psych: PsychologyReportTradingPsychology) -> PsychologyReportSection {
        var metrics: [PsychologyReportMetricRow] = []
        if let emotion = psych.mostCommonEmotion {
            metrics.append(PsychologyReportMetricRow(label: "Most Common", value: emotion))
        }
        if psych.fomoTradeCount > 0 {
            metrics.append(PsychologyReportMetricRow(label: "FOMO Trades", value: NumberDisplay.integer(psych.fomoTradeCount)))
        }
        if psych.frustratedTradeCount > 0 {
            metrics.append(PsychologyReportMetricRow(label: "Frustrated Trades", value: NumberDisplay.integer(psych.frustratedTradeCount)))
        }
        return PsychologyReportSection(id: "emotion", title: "Emotions", subtitle: nil, bullets: [], metrics: metrics)
    }

    private static func mentalStateMetrics(_ summary: PsychologyReportCheckInSummary) -> [PsychologyReportMetricRow] {
        var rows: [PsychologyReportMetricRow] = []
        if let v = summary.averageEnergy {
            rows.append(PsychologyReportMetricRow(label: "Avg Energy", value: NumberDisplay.ratingOutOfFive(v)))
        }
        if let v = summary.averageMorningRating {
            rows.append(PsychologyReportMetricRow(label: "Avg Morning", value: NumberDisplay.ratingOutOfFive(v)))
        }
        return rows
    }

    private static func afterLossesSection(_ behavior: PsychologyReportBehaviorSummary) -> PsychologyReportSection {
        var bullets: [String] = []
        if let after = behavior.afterTwoLossesWinRate, let base = behavior.afterTwoLossesBaselineWinRate {
            bullets.append("\(behavior.afterLossLabel): \(NumberDisplay.percent(after * 100, minimumFractionDigits: 0, maximumFractionDigits: 0)) vs \(NumberDisplay.percent(base * 100, minimumFractionDigits: 0, maximumFractionDigits: 0)) baseline")
        }
        return PsychologyReportSection(id: "afterLosses", title: "After Losses", subtitle: nil, bullets: bullets, metrics: [])
    }

    private static func tradeFrequencySection(_ behavior: PsychologyReportBehaviorSummary) -> PsychologyReportSection {
        var metrics: [PsychologyReportMetricRow] = []
        if let avg = behavior.averageTradesPerDay {
            metrics.append(PsychologyReportMetricRow(label: "Trades/Day", value: NumberDisplay.decimal(avg, minimumFractionDigits: 1, maximumFractionDigits: 1)))
        }
        if let early = behavior.earlyTradeAvgPnL, let late = behavior.lateTradeAvgPnL {
            metrics.append(PsychologyReportMetricRow(label: behavior.earlyLabel, value: NumberDisplay.currency(early, minimumFractionDigits: 0, maximumFractionDigits: 0)))
            metrics.append(PsychologyReportMetricRow(label: behavior.lateLabel, value: NumberDisplay.currency(late, minimumFractionDigits: 0, maximumFractionDigits: 0)))
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

    private static func buildEmotionBreakdown(_ trades: [Trade]) -> [PsychologyReportEmotionRow] {
        var grouped: [String: [Trade]] = [:]
        for trade in trades {
            guard let emotion = normalizedEmotion(trade.emotion) else { continue }
            grouped[emotion, default: []].append(trade)
        }
        return grouped
            .map { label, rows in
                PsychologyReportEmotionRow(
                    label: label,
                    metrics: TraderPsychologyAnalyticsEngine.metrics(for: rows)
                )
            }
            .sorted { lhs, rhs in
                if lhs.metrics.tradeCount != rhs.metrics.tradeCount {
                    return lhs.metrics.tradeCount > rhs.metrics.tradeCount
                }
                let left = lhs.metrics.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
                let right = rhs.metrics.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
                return left > right
            }
            .prefix(8)
            .map { $0 }
    }

    private static func normalizedEmotion(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return TradeReviewCatalog.emotions.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
    }
}
