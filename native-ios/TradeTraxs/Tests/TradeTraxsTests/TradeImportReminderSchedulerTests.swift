import XCTest
@testable import TradeTraxs

final class TradeImportReminderSchedulerTests: XCTestCase {
    func testPlannedWeekdayRequestsCountAndTimes() {
        let requests = TradeImportReminderScheduler.plannedWeekdayRequests
        XCTAssertEqual(requests.count, 10)

        let morning = requests.filter { $0.hour == 11 && $0.minute == 15 }
        let afternoon = requests.filter { $0.hour == 16 && $0.minute == 0 }
        XCTAssertEqual(morning.count, 5)
        XCTAssertEqual(afternoon.count, 5)
    }

    func testPlannedWeekdayRequestsNoWeekend() {
        let weekdays = Set(TradeImportReminderScheduler.plannedWeekdayRequests.map(\.weekday))
        XCTAssertEqual(weekdays, Set([2, 3, 4, 5, 6]))
        XCTAssertFalse(weekdays.contains(1))
        XCTAssertFalse(weekdays.contains(7))
    }

    func testCanonicalIdentifiersStable() {
        let ids = TradeImportReminderScheduler.canonicalIdentifiers
        XCTAssertEqual(ids.count, 10)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix(TradeImportReminderScheduler.identifierPrefix) })
        XCTAssertEqual(Set(ids.filter { $0.contains(":1115:") }).count, 5)
        XCTAssertEqual(Set(ids.filter { $0.contains(":1600:") }).count, 5)
    }

    func testNotificationCopy() {
        XCTAssertEqual(TradeImportReminderScheduler.notificationBody, "Did you import any trades today?")
    }

    func testDateComponentsUseAmericaNewYork() {
        let request = TradeImportReminderScheduler.plannedWeekdayRequests[0]
        let components = WeekdayEasternReminderSupport.dateComponents(
            weekday: request.weekday,
            hour: request.hour,
            minute: request.minute
        )
        XCTAssertEqual(components.timeZone, TimeZone(identifier: "America/New_York"))
    }

    func testLegacyIdentifiersListedForCleanup() {
        XCTAssertTrue(
            TradeImportReminderScheduler.legacyIdentifiers.contains("trade-import-reminder:1115-et")
        )
        XCTAssertTrue(
            TradeImportReminderScheduler.legacyIdentifiers.contains("trade-import-reminder:1600-et")
        )
    }

    func testShouldRemoveOnlyTradeImportFamily() {
        XCTAssertTrue(TradeImportReminderScheduler.shouldRemove(identifier: "trade-import-reminder:1115:wd2"))
        XCTAssertTrue(TradeImportReminderScheduler.shouldRemove(identifier: "trade-import-reminder:1115-et"))
        XCTAssertFalse(TradeImportReminderScheduler.shouldRemove(identifier: "daily-check-in:0915:wd2"))
        XCTAssertFalse(TradeImportReminderScheduler.shouldRemove(identifier: "push:activity:123"))
    }

    func testRescheduleDoesNotExpandIdentifierSet() {
        let first = Set(TradeImportReminderScheduler.canonicalIdentifiers)
        let second = Set(TradeImportReminderScheduler.canonicalIdentifiers)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 10)
    }
}
