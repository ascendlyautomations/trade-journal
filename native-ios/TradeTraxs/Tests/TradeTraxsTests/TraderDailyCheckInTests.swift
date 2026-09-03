import XCTest
@testable import TradeTraxs

final class TraderDailyCheckInTests: XCTestCase {
    func testValidationRejectsOutOfRangeRatings() {
        var draft = TraderDailyCheckInDraft.empty(for: "2026-09-02")
        draft.sleepHours = 7.5
        draft.stressLevel = 6
        XCTAssertEqual(
            TraderDailyCheckInValidation.validate(draft),
            "Stress must be between 1 and 5."
        )
    }

    func testValidationRequiresSleepHours() {
        var draft = TraderDailyCheckInDraft.empty(for: "2026-09-02")
        XCTAssertEqual(
            TraderDailyCheckInValidation.validate(draft),
            "Enter hours of sleep between 0 and 24."
        )
    }

    func testValidationAcceptsDecimalSleepHours() {
        var draft = TraderDailyCheckInDraft.empty(for: "2026-09-02")
        draft.sleepHours = Decimal(string: "7.5")
        XCTAssertNil(TraderDailyCheckInValidation.validate(draft))
    }

    func testCompleteCheckInRequiresAllFields() {
        let incomplete = TraderDailyCheckIn(
            id: TraderDailyCheckInID("id"),
            ownerProfileID: ProfileID("user"),
            checkInDate: "2026-09-02",
            sleepHours: nil,
            sleepQuality: 4,
            morningRating: 4,
            stressLevel: 2,
            energyLevel: 4,
            focusLevel: 4,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        XCTAssertFalse(incomplete.isComplete)

        let complete = TraderDailyCheckIn(
            id: TraderDailyCheckInID("id"),
            ownerProfileID: ProfileID("user"),
            checkInDate: "2026-09-02",
            sleepHours: 7.5,
            sleepQuality: 4,
            morningRating: 4,
            stressLevel: 2,
            energyLevel: 4,
            focusLevel: 4,
            notes: "Feeling good",
            createdAt: Date(),
            updatedAt: Date()
        )
        XCTAssertTrue(complete.isComplete)
    }

    func testTradeDateKeyUsesEasternSemantics() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let components = DateComponents(year: 2026, month: 9, day: 2, hour: 1, minute: 30)
        let date = calendar.date(from: components)!
        XCTAssertEqual(
            TraderPsychologyAnalyticsFoundation.tradeDateKey(for: date),
            "2026-09-02"
        )
    }

    func testCorrelateJoinsTradesToCheckInsByDate() throws {
        let entry = ISO8601.date(from: "2026-09-02T14:00:00.000Z")!
        let trade = Trade(
            id: TradeID("t1"),
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
            realizedPnL: Money(amount: 100),
            riskReward: nil,
            points: nil,
            sessionLabel: "NY",
            visibility: .private,
            publicCaption: nil,
            createdAt: entry,
            updatedAt: entry
        )
        let checkIn = TraderDailyCheckIn(
            id: TraderDailyCheckInID("c1"),
            ownerProfileID: ProfileID("user"),
            checkInDate: TraderPsychologyAnalyticsFoundation.tradeDateKey(for: trade),
            sleepHours: 8,
            sleepQuality: 4,
            morningRating: 4,
            stressLevel: 2,
            energyLevel: 4,
            focusLevel: 5,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let correlated = TraderPsychologyAnalyticsFoundation.correlate(
            trades: [trade],
            checkIns: [checkIn]
        )
        XCTAssertEqual(correlated.count, 1)
        XCTAssertEqual(correlated[0].dailyCheckIn?.id, checkIn.id)
    }

    func testSleepHoursBands() {
        XCTAssertEqual(
            TraderPsychologyAnalyticsFoundation.SleepHoursBand.resolve(7.5),
            .sevenToNine
        )
        XCTAssertEqual(
            TraderPsychologyAnalyticsFoundation.SleepHoursBand.resolve(5.5),
            .underSix
        )
    }

    func testBehaviorSnapshotCountsConsecutiveLosses() {
        let base = ISO8601.date(from: "2026-09-02T14:00:00.000Z")!
        func trade(id: String, pnl: Decimal, offsetHours: Int) -> Trade {
            let at = base.addingTimeInterval(TimeInterval(offsetHours * 3600))
            return Trade(
                id: TradeID(id),
                ownerProfileID: ProfileID("user"),
                accountID: nil,
                symbol: Symbol(ticker: "ES"),
                side: .long,
                mode: .live,
                quantity: 1,
                entryPrice: 100,
                exitPrice: nil,
                entryAt: at,
                exitAt: nil,
                realizedPnL: Money(amount: pnl),
                riskReward: nil,
                points: nil,
                sessionLabel: nil,
                visibility: .private,
                publicCaption: nil,
                createdAt: at,
                updatedAt: at
            )
        }

        let trades = [
            trade(id: "1", pnl: 50, offsetHours: 0),
            trade(id: "2", pnl: -20, offsetHours: 1),
            trade(id: "3", pnl: -30, offsetHours: 2),
        ]
        let snapshot = TraderPsychologyAnalyticsFoundation.behaviorSnapshot(
            for: trades,
            endingAt: TradeID("3")
        )
        XCTAssertEqual(snapshot?.consecutiveLosses, 2)
        XCTAssertEqual(snapshot?.consecutiveWins, 0)
    }
}
