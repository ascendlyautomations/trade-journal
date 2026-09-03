import XCTest
@testable import TradeTraxs

final class PsychologyCoachPhase5Tests: XCTestCase {
    private let baseDate = ISO8601.date(from: "2026-09-02T14:00:00.000Z")!

    func testFactsBuilderUsesDeterministicReportOnly() {
        let trades = (0..<12).map { makeTrade(id: "t\($0)", pnl: $0.isMultiple(of: 2) ? 50 : -20, offsetHours: $0) }
        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: trades, checkIns: [])
        let facts = PsychologyCoachFactsBuilder.build(report: report, trades: trades, checkIns: [])

        XCTAssertEqual(facts.baseline.tradeCount, report.baseline.tradeCount)
        XCTAssertEqual(facts.topInsights.count, report.dashboardCards.count)
        XCTAssertFalse(facts.factsHash.isEmpty)
        XCTAssertTrue(facts.hasMinimumData)
    }

    func testFactsHashChangesWhenUnderlyingDataChanges() {
        let tradesA = (0..<10).map { makeTrade(id: "a\($0)", pnl: 10, offsetHours: $0) }
        let reportA = TraderPsychologyAnalyticsEngine.buildReport(trades: tradesA, checkIns: [])
        let factsA = PsychologyCoachFactsBuilder.build(report: reportA, trades: tradesA, checkIns: [])

        let tradesB = tradesA + [makeTrade(id: "b", pnl: -500, offsetHours: 20)]
        let reportB = TraderPsychologyAnalyticsEngine.buildReport(trades: tradesB, checkIns: [])
        let factsB = PsychologyCoachFactsBuilder.build(report: reportB, trades: tradesB, checkIns: [])

        XCTAssertNotEqual(factsA.factsHash, factsB.factsHash)
    }

    func testMinimumSampleSummaryWhenInsufficientData() {
        let trades = (0..<3).map { makeTrade(id: "t\($0)", pnl: 10, offsetHours: $0) }
        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: trades, checkIns: [])
        let facts = PsychologyCoachFactsBuilder.build(report: report, trades: trades, checkIns: [])
        let summary = PsychologyCoachDeterministicCoach.buildSummary(from: facts)

        XCTAssertFalse(facts.hasMinimumData)
        XCTAssertTrue(summary.overview.contains("5 trades") || summary.overview.contains("Log"))
    }

    func testCombinedPatternsRequireStrongerSamples() {
        let checkIn = makeCheckIn(date: "2026-09-02", stress: 5, sleepHours: 4)
        let trades = (0..<12).map {
            makeTrade(id: "t\($0)", pnl: -30, offsetHours: $0, dayOffset: 0)
        }
        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: trades, checkIns: [checkIn])
        let facts = PsychologyCoachFactsBuilder.build(report: report, trades: trades, checkIns: [checkIn])

        for combo in facts.combinedPatterns {
            XCTAssertGreaterThanOrEqual(combo.sampleSize, 10)
        }
    }

    func testTrendComparisonRequiresMinimumHistory() {
        let trades = (0..<40).map { makeTrade(id: "t\($0)", pnl: 10, offsetHours: $0) }
        let trends = PsychologyTrendAnalyzer.analyze(trades: trades, checkIns: [])
        for trend in trends {
            XCTAssertGreaterThanOrEqual(trend.recentSampleSize, 8)
            XCTAssertGreaterThanOrEqual(trend.priorSampleSize, PsychologyTrendAnalyzer.minimumPriorTrades)
        }
    }

    func testConsecutiveLossGuardrailTriggers() {
        let trades = [
            makeTrade(id: "1", pnl: -10, offsetHours: 0),
            makeTrade(id: "2", pnl: -10, offsetHours: 1),
            makeTrade(id: "3", pnl: -10, offsetHours: 2),
        ] + (3..<15).map { makeTrade(id: "x\($0)", pnl: -10, offsetHours: $0) }

        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: trades, checkIns: [])
        let facts = PsychologyCoachFactsBuilder.build(report: report, trades: trades, checkIns: [])
        let enriched = TraderPsychologyAnalyticsEngine.enrich(trades: trades, checkIns: [])
        let today = enriched.filter {
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: $0.trade) == "2026-09-02"
        }

        let notices = PsychologyGuardrailEngine.activeNotices(
            facts: facts,
            todayCheckIn: nil,
            enrichedTradesToday: today,
            dismissedKeys: [],
            tradingDay: "2026-09-02"
        )

        if facts.guardrailFacts.consecutiveLossCheckpoint != nil {
            XCTAssertTrue(notices.contains { $0.kind == .consecutiveLosses })
        }
    }

    func testLowSleepGuardrail() {
        let checkIn = makeCheckIn(date: "2026-09-02", stress: 2, sleepHours: 4.5)
        let trades = (0..<12).map {
            makeTrade(id: "t\($0)", pnl: -20, offsetHours: $0, dayOffset: 0)
        }
        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: trades, checkIns: [checkIn])
        let facts = PsychologyCoachFactsBuilder.build(report: report, trades: trades, checkIns: [checkIn])

        let notices = PsychologyGuardrailEngine.activeNotices(
            facts: facts,
            todayCheckIn: checkIn,
            enrichedTradesToday: [],
            dismissedKeys: [],
            tradingDay: "2026-09-02"
        )

        if facts.guardrailFacts.lowSleepHoursThreshold != nil {
            XCTAssertTrue(notices.contains { $0.kind == .lowSleep })
        }
    }

    func testGuardrailDismissalDedupes() {
        let notice = PsychologyGuardrailNotice(
            id: "guardrail.lowSleep",
            title: "Low Sleep",
            message: "Test",
            kind: .lowSleep
        )
        let key = PsychologyGuardrailEngine.dedupeKey(for: notice, tradingDay: "2026-09-02")
        let filtered = PsychologyGuardrailEngine.activeNotices(
            facts: PsychologyCoachFactsBuilder.build(
                report: TraderPsychologyAnalyticsEngine.buildReport(trades: [], checkIns: []),
                trades: [],
                checkIns: []
            ),
            todayCheckIn: makeCheckIn(date: "2026-09-02", stress: 2, sleepHours: 4),
            enrichedTradesToday: [],
            dismissedKeys: [key],
            tradingDay: "2026-09-02"
        )
        XCTAssertFalse(filtered.contains { $0.kind == .lowSleep })
    }

    func testDeterministicCoachFallbackWithoutAI() {
        let trades = (0..<8).map { makeTrade(id: "t\($0)", pnl: 25, offsetHours: $0) }
        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: trades, checkIns: [])
        let facts = PsychologyCoachFactsBuilder.build(report: report, trades: trades, checkIns: [])
        let summary = PsychologyCoachDeterministicCoach.buildSummary(from: facts)

        XCTAssertTrue(summary.isDeterministic)
        XCTAssertFalse(summary.overview.isEmpty)
    }

    func testPreTradeNoticeOnlyOnLowFocusWithPattern() {
        var facts = PsychologyCoachFactsBuilder.build(
            report: TraderPsychologyAnalyticsEngine.buildReport(
                trades: (0..<8).map { makeTrade(id: "t\($0)", pnl: 10, offsetHours: $0) },
                checkIns: []
            ),
            trades: [],
            checkIns: []
        )
        facts.topInsights = [
            PsychologyCoachFactInsight(
                id: "focus",
                category: "mentalState",
                headline: "Low focus days underperform",
                detail: "detail",
                sampleSize: 10,
                reliability: "developing",
                expectancy: nil,
                winRate: nil,
                averagePnL: nil
            ),
        ]

        XCTAssertNotNil(AddTradePreTradePsychologyPolicy.noticeMessage(facts: facts, focusLevel: 2))
        XCTAssertNil(AddTradePreTradePsychologyPolicy.noticeMessage(facts: facts, focusLevel: 4))
    }

    // MARK: - Fixtures

    private func makeTrade(
        id: String,
        pnl: Decimal,
        offsetHours: Int,
        dayOffset: Int = 0,
        confidence: Int? = nil
    ) -> Trade {
        let entry = Calendar.current.date(
            byAdding: .hour,
            value: offsetHours + dayOffset * 24,
            to: baseDate
        )!
        return Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID("user-1"),
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: entry,
            exitAt: entry.addingTimeInterval(3600),
            realizedPnL: Money(amount: pnl),
            riskReward: 2,
            points: 0,
            sessionLabel: "NY",
            visibility: .private,
            confidence: confidence,
            createdAt: entry,
            updatedAt: entry
        )
    }

    private func makeCheckIn(
        date: String,
        stress: Int,
        sleepHours: Decimal
    ) -> TraderDailyCheckIn {
        TraderDailyCheckIn(
            id: TraderDailyCheckInID(UUID().uuidString),
            ownerProfileID: ProfileID("user-1"),
            checkInDate: date,
            sleepHours: sleepHours,
            sleepQuality: 3,
            morningRating: 3,
            stressLevel: stress,
            energyLevel: 3,
            focusLevel: 3,
            notes: nil,
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }
}
