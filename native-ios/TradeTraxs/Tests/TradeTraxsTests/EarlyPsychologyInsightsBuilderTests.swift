import XCTest
@testable import TradeTraxs

final class EarlyPsychologyInsightsBuilderTests: XCTestCase {
    func testMatchedDayAggregatesPnLOncePerDay() {
        let entry = ISO8601.date(from: "2026-09-02T14:00:00.000Z")!
        let tradeA = makeTrade(id: "a", entry: entry, pnl: 100)
        let tradeB = makeTrade(id: "b", entry: entry.addingTimeInterval(3600), pnl: -40)
        let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: tradeA)
        let checkIn = completeCheckIn(date: key)

        let days = EarlyPsychologyInsightsBuilder.buildMatchedTradingDays(
            trades: [tradeA, tradeB],
            checkIns: [checkIn]
        )
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].dailyPnL, 60)
        XCTAssertEqual(days[0].tradeCount, 2)
    }

    func testEarlyCardsIncludeOverviewForSingleMatchedDay() {
        let entry = ISO8601.date(from: "2026-09-02T14:00:00.000Z")!
        let trade = makeTrade(id: "a", entry: entry, pnl: 85)
        let key = TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade)
        let checkIn = completeCheckIn(date: key, sleepQuality: 5, focusLevel: 5)

        let cards = EarlyPsychologyInsightsBuilder.build(trades: [trade], checkIns: [checkIn])
        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(cards.contains { $0.id == "matchedDays.overview" })
        XCTAssertTrue(cards.allSatisfy { $0.reliability != .insufficient })
    }

    func testMergePrefersReportCardsAndDedupes() {
        let reportCard = PsychologyInsightCard(
            id: "sleep.compare",
            category: .sleep,
            sectionTitle: "Sleep",
            headline: "Report",
            detail: "Detail",
            sampleSize: 10,
            reliability: .developing,
            rankingScore: 1
        )
        let early = EarlyPsychologyInsightsBuilder.build(trades: [], checkIns: [])
        let merged = EarlyPsychologyInsightsBuilder.merge(early: early, reportCards: [reportCard])
        XCTAssertEqual(merged.first?.id, "sleep.compare")
    }

    private func completeCheckIn(
        date: String,
        sleepQuality: Int = 4,
        focusLevel: Int = 4
    ) -> TraderDailyCheckIn {
        TraderDailyCheckIn(
            id: TraderDailyCheckInID("c-\(date)"),
            ownerProfileID: ProfileID("user"),
            checkInDate: date,
            sleepHours: 7,
            sleepQuality: sleepQuality,
            morningRating: 4,
            stressLevel: 2,
            energyLevel: 4,
            focusLevel: focusLevel,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeTrade(id: String, entry: Date, pnl: Decimal) -> Trade {
        Trade(
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
            createdAt: entry,
            updatedAt: entry
        )
    }
}
