import XCTest
@testable import TradeTraxs

final class PsychologyReportExpansionTests: XCTestCase {
    private let baseDate = ISO8601.date(from: "2026-09-02T14:00:00.000Z")!

    func testCheckInHistoryAggregatorUsesEasternTradeDate() {
        let checkIn = makeCheckIn(date: "2026-09-02", sleep: 7.5, focus: 5, stress: 2)
        let trade = makeTrade(id: "1", pnl: 100, offsetHours: 0)
        let summaries = CheckInHistoryAggregator.buildSummaries(
            checkIns: [checkIn],
            trades: [trade]
        )
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].dateKey, "2026-09-02")
        XCTAssertEqual(summaries[0].tradeCount, 1)
        XCTAssertEqual(summaries[0].totalPnL, 100)
    }

    func testDayDetailMatchesTradesForDate() {
        let checkIn = makeCheckIn(date: "2026-09-02", sleep: 7, focus: 4, stress: 2)
        let trade = makeTrade(id: "1", pnl: 50, offsetHours: 0)
        let other = makeTrade(id: "2", pnl: -20, offsetHours: 24, dayOffset: 1)
        let detail = CheckInHistoryAggregator.buildDetail(
            dateKey: "2026-09-02",
            checkIns: [checkIn],
            trades: [trade, other]
        )
        XCTAssertEqual(detail.trades.count, 1)
        XCTAssertEqual(detail.checkIn?.checkInDate, "2026-09-02")
        XCTAssertEqual(detail.metrics.tradeCount, 1)
    }

    func testPsychologyReportGeneratorProducesWeeklyReport() {
        let trades = (0..<15).map { makeTrade(id: "t\($0)", pnl: $0.isMultiple(of: 2) ? 40 : -15, offsetHours: $0) }
        let ref = PsychologyReportPeriodRef(template: .weekly, periodID: "week:2026-09-01")
        let report = PsychologyReportGenerator.generate(
            periodRef: ref,
            trades: trades,
            checkIns: [],
            now: baseDate
        )
        XCTAssertEqual(report.periodRef.template, .weekly)
        XCTAssertFalse(report.factsHash.isEmpty)
        XCTAssertTrue(report.sections.contains { $0.id == "performance" })
    }

    func testPsychologyReportPersistsAnalyticsEnginePayload() {
        var trades: [Trade] = []
        for index in 0..<24 {
            var trade = makeTrade(
                id: "t\(index)",
                pnl: index.isMultiple(of: 2) ? 80 : -20,
                offsetHours: index
            )
            trade.followedPlan = index.isMultiple(of: 3)
            trade.emotion = index.isMultiple(of: 4) ? "Calm" : "FOMO"
            trades.append(trade)
        }
        let checkIns = (0..<8).map { makeCheckIn(date: "2026-09-0\($0 + 1)", sleep: 7.5, focus: 5, stress: 1) }
        let ref = PsychologyReportPeriodRef(template: .discipline, periodID: "rolling:90d")
        let bounds = PsychologyReportPeriods.bounds(for: ref, now: baseDate)
        let periodTrades = trades.filter { $0.entryAt >= bounds.start && $0.entryAt <= bounds.end }
        let periodCheckIns = checkIns.filter {
            let startKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.start)
            let endKey = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.end)
            return $0.checkInDate >= startKey && $0.checkInDate <= endKey
        }
        let analytics = TraderPsychologyAnalyticsEngine.buildReport(
            trades: periodTrades,
            checkIns: periodCheckIns,
            now: baseDate
        )
        let report = PsychologyReportGenerator.generate(
            periodRef: ref,
            trades: trades,
            checkIns: checkIns,
            now: baseDate
        )
        XCTAssertEqual(report.analyticsSections, analytics.sections)
        XCTAssertEqual(report.insightCards, analytics.dashboardCards)
        XCTAssertGreaterThanOrEqual(report.emotionBreakdown.count, 2)
        XCTAssertGreaterThan(report.planTaggedTradeCount, 0)
    }

    func testPsychologyReportRollingBoundsSevenDays() {
        let ref = PsychologyReportPeriodRef(template: .discipline, periodID: "rolling:7d")
        let now = ISO8601.date(from: "2026-09-02T14:00:00.000Z")!
        let bounds = PsychologyReportPeriods.bounds(for: ref, now: now)
        XCTAssertEqual(bounds.dateRangeLabel, "Last 7 days")
        let calendar = TradingReportPeriods.eastern
        let expectedStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        XCTAssertEqual(
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: bounds.start),
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: expectedStart ?? now)
        )
    }

    func testPsychologyReportPeriodRefParsing() {
        let id = ReportID("psych_weekly:week:2026-08-31")
        let ref = PsychologyReportPeriodRef.parse(reportID: id)
        XCTAssertEqual(ref?.template, .weekly)
        XCTAssertEqual(ref?.periodID, "week:2026-08-31")
    }

    func testMonthlyComparisonsRequireMinimumSamples() {
        let trades = (0..<80).enumerated().map { index, _ in
            makeTrade(id: "t\(index)", pnl: index.isMultiple(of: 2) ? 30 : -10, offsetHours: index)
        }
        let ref = PsychologyReportPeriodRef(template: .monthly, periodID: "month:2026-09")
        let report = PsychologyReportGenerator.generate(
            periodRef: ref,
            trades: trades,
            checkIns: [],
            now: baseDate
        )
        for comparison in report.comparisons {
            XCTAssertFalse(comparison.headline.isEmpty)
        }
    }

    func testPsychologyReportFactsBuilderUsesReportMetricsOnly() {
        let trades = (0..<10).map { makeTrade(id: "t\($0)", pnl: 20, offsetHours: $0) }
        let ref = PsychologyReportPeriodRef(template: .discipline, periodID: "rolling:90d")
        let report = PsychologyReportGenerator.generate(periodRef: ref, trades: trades, checkIns: [])
        let facts = PsychologyReportFactsBuilder.build(from: report)
        XCTAssertEqual(facts.factsHash, report.factsHash)
        XCTAssertEqual(facts.baseline.tradeCount, report.performance.tradeCount)
    }

    func testHistoricalPeriodCatalog() {
        let trades = (0..<100).enumerated().map { index, _ in
            makeTrade(id: "t\(index)", pnl: 10, offsetHours: -(index * 12))
        }
        let catalog = PsychologyReportPeriods.availableCatalog(trades: trades, now: baseDate)
        XCTAssertTrue(catalog.contains { $0.template == .weekly })
        XCTAssertTrue(catalog.contains { $0.template == .discipline })
        XCTAssertGreaterThanOrEqual(catalog.filter { $0.template == .weekly }.count, 2)
    }

    private func makeTrade(
        id: String,
        pnl: Decimal,
        offsetHours: Int,
        dayOffset: Int = 0
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
            createdAt: entry,
            updatedAt: entry
        )
    }

    private func makeCheckIn(date: String, sleep: Double, focus: Int, stress: Int) -> TraderDailyCheckIn {
        TraderDailyCheckIn(
            id: TraderDailyCheckInID(UUID().uuidString),
            ownerProfileID: ProfileID("user-1"),
            checkInDate: date,
            sleepHours: Decimal(sleep),
            sleepQuality: 4,
            morningRating: 4,
            stressLevel: stress,
            energyLevel: 4,
            focusLevel: focus,
            notes: nil,
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }
}
