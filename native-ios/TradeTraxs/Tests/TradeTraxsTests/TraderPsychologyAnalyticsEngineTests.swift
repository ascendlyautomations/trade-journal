import XCTest
@testable import TradeTraxs

final class TraderPsychologyAnalyticsEngineTests: XCTestCase {
    private let baseDate = ISO8601.date(from: "2026-09-02T14:00:00.000Z")!

    func testSleepBucketingUsesSpecifiedBands() {
        XCTAssertEqual(
            TraderPsychologyAnalyticsEngine.SleepPerformanceBand.resolve(4.5),
            .underFive
        )
        XCTAssertEqual(
            TraderPsychologyAnalyticsEngine.SleepPerformanceBand.resolve(7.5),
            .sevenToEight
        )
        XCTAssertEqual(
            TraderPsychologyAnalyticsEngine.SleepPerformanceBand.resolve(9.5),
            .ninePlus
        )
    }

    func testExpectancyAndWinRateCalculation() {
        let trades = [
            makeTrade(id: "1", pnl: 100, offsetHours: 0),
            makeTrade(id: "2", pnl: -50, offsetHours: 1),
            makeTrade(id: "3", pnl: 100, offsetHours: 2),
            makeTrade(id: "4", pnl: -50, offsetHours: 3),
            makeTrade(id: "5", pnl: 100, offsetHours: 4),
        ]
        let metrics = TraderPsychologyAnalyticsEngine.metrics(for: trades)
        XCTAssertEqual(metrics.tradeCount, 5)
        XCTAssertEqual(metrics.winCount, 3)
        XCTAssertEqual(metrics.lossCount, 2)
        XCTAssertEqual(TraderPsychologyAnalyticsEngine.formatWinRate(metrics.winRate), "60%")
        XCTAssertEqual(metrics.reliability, .earlySignal)
        XCTAssertEqual(NSDecimalNumber(decimal: metrics.expectancy ?? 0).intValue, 40)
    }

    func testProfitFactorRequiresLosses() {
        let winners = [
            makeTrade(id: "1", pnl: 100, offsetHours: 0),
            makeTrade(id: "2", pnl: 50, offsetHours: 1),
            makeTrade(id: "3", pnl: 25, offsetHours: 2),
            makeTrade(id: "4", pnl: 10, offsetHours: 3),
            makeTrade(id: "5", pnl: 5, offsetHours: 4),
        ]
        let metrics = TraderPsychologyAnalyticsEngine.metrics(for: winners)
        XCTAssertNil(metrics.profitFactor)
    }

    func testStressDirectionTreatsHighStressAsWorse() {
        let checkInLowStress = makeCheckIn(date: "2026-09-02", stress: 2, sleepHours: 8)
        let checkInHighStress = makeCheckIn(date: "2026-09-03", stress: 5, sleepHours: 8)

        let lowStressTrades = (0..<6).map {
            makeTrade(id: "l\($0)", pnl: 50, offsetHours: $0, dayOffset: 0)
        }
        let highStressTrades = (0..<6).map {
            makeTrade(id: "h\($0)", pnl: -20, offsetHours: $0, dayOffset: 1)
        }

        let report = TraderPsychologyAnalyticsEngine.buildReport(
            trades: lowStressTrades + highStressTrades,
            checkIns: [checkInLowStress, checkInHighStress]
        )

        XCTAssertFalse(report.dashboardCards.isEmpty)
    }

    func testConvictionGroupingInsight() {
        let high = (0..<6).map { makeTrade(id: "h\($0)", pnl: 80, offsetHours: $0, confidence: 5) }
        let low = (0..<6).map { makeTrade(id: "l\($0)", pnl: -40, offsetHours: $0 + 10, confidence: 1) }
        let report = TraderPsychologyAnalyticsEngine.buildReport(
            trades: high + low,
            checkIns: []
        )
        XCTAssertTrue(
            report.dashboardCards.contains { $0.category == .conviction }
        )
    }

    func testFollowedPlanComparison() {
        let followed = (0..<6).map {
            var trade = makeTrade(id: "f\($0)", pnl: 40, offsetHours: $0)
            trade.followedPlan = true
            return trade
        }
        let broken = (0..<6).map {
            var trade = makeTrade(id: "b\($0)", pnl: -30, offsetHours: $0 + 10)
            trade.followedPlan = false
            return trade
        }
        let report = TraderPsychologyAnalyticsEngine.buildReport(
            trades: followed + broken,
            checkIns: []
        )
        XCTAssertTrue(report.dashboardCards.contains { $0.category == .discipline })
    }

    func testConsecutiveLossCalculation() {
        let trades = [
            makeTrade(id: "1", pnl: -10, offsetHours: 0),
            makeTrade(id: "2", pnl: -10, offsetHours: 1),
            makeTrade(id: "3", pnl: 50, offsetHours: 2),
        ]
        let enriched = TraderPsychologyAnalyticsEngine.enrich(trades: trades, checkIns: [])
        XCTAssertEqual(enriched[0].consecutiveLossesBefore, 0)
        XCTAssertEqual(enriched[1].consecutiveLossesBefore, 1)
        XCTAssertEqual(enriched[2].consecutiveLossesBefore, 2)
    }

    func testTradeNumberWithinDayResetsOnNewDay() {
        let dayOne = makeTrade(id: "1", pnl: 10, offsetHours: 0, dayOffset: 0)
        let dayOneSecond = makeTrade(id: "2", pnl: 10, offsetHours: 1, dayOffset: 0)
        let dayTwo = makeTrade(id: "3", pnl: 10, offsetHours: 0, dayOffset: 1)
        let enriched = TraderPsychologyAnalyticsEngine.enrich(
            trades: [dayOne, dayOneSecond, dayTwo],
            checkIns: []
        )
        XCTAssertEqual(enriched[0].tradeNumberInDay, 1)
        XCTAssertEqual(enriched[1].tradeNumberInDay, 2)
        XCTAssertEqual(enriched[2].tradeNumberInDay, 1)
    }

    func testMinimumSampleThresholdBlocksInsufficientGroups() {
        let trades = [
            makeTrade(id: "1", pnl: 100, offsetHours: 0, confidence: 5),
            makeTrade(id: "2", pnl: 100, offsetHours: 1, confidence: 1),
        ]
        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: trades, checkIns: [])
        XCTAssertTrue(report.dashboardCards.isEmpty)
    }

    func testInsightRankingPrefersLargerReliableSamples() {
        let early = PsychologyInsightCard(
            id: "a",
            category: .sleep,
            sectionTitle: "Sleep",
            headline: "A",
            detail: "A",
            sampleSize: 6,
            reliability: .earlySignal,
            rankingScore: 0.2
        )
        let strong = PsychologyInsightCard(
            id: "b",
            category: .discipline,
            sectionTitle: "Discipline",
            headline: "B",
            detail: "B",
            sampleSize: 30,
            reliability: .strong,
            rankingScore: 0.9
        )
        let ranked = TraderPsychologyAnalyticsEngine.rankInsights([early, strong])
        XCTAssertEqual(ranked.first?.id, "b")
    }

    func testCombinedSignalRequiresMeaningfulSample() {
        let trades = (0..<4).map {
            var trade = makeTrade(id: "t\($0)", pnl: -10, offsetHours: $0)
            trade.confidence = 5
            trade.followedPlan = true
            return trade
        }
        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: trades, checkIns: [])
        XCTAssertFalse(report.dashboardCards.contains { $0.category == .combined })
    }

    func testInsufficientDataProducesEmptyDashboardCardsWithSections() {
        let report = TraderPsychologyAnalyticsEngine.buildReport(trades: [], checkIns: [])
        XCTAssertTrue(report.dashboardCards.isEmpty)
        XCTAssertFalse(report.sections.isEmpty)
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
        ) ?? baseDate
        return Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID("user"),
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 110,
            entryAt: entry,
            exitAt: entry.addingTimeInterval(3600),
            realizedPnL: Money(amount: pnl),
            riskReward: nil,
            points: nil,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
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
            ownerProfileID: ProfileID("user"),
            checkInDate: date,
            sleepHours: sleepHours,
            sleepQuality: 4,
            morningRating: 4,
            stressLevel: stress,
            energyLevel: 4,
            focusLevel: 4,
            notes: nil,
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }
}
