import XCTest
@testable import TradeTraxs

final class DailyCheckInReminderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    func testPlannedItemsSkipsWeekends() {
        // Thursday 2026-09-03 08:00 ET
        let now = makeDate(year: 2026, month: 9, day: 3, hour: 8, minute: 0)
        let items = DailyCheckInReminderScheduler.plannedItems(
            now: now,
            calendar: calendar,
            isTodayCompleted: false,
            todayDateKey: "2026-09-03",
            dateKeyForMoment: { _ in "2026-09-03" }
        )

        let weekdaySet = Set(items.map { calendar.component(.weekday, from: $0.fireDate) })
        XCTAssertFalse(weekdaySet.contains(1)) // Sunday
        XCTAssertFalse(weekdaySet.contains(7)) // Saturday
        XCTAssertTrue(weekdaySet.isSubset(of: Set([2, 3, 4, 5, 6])))
    }

    func testPlannedItemsSkipsTodayWhenCompleted() {
        let now = makeDate(year: 2026, month: 9, day: 3, hour: 8, minute: 0)
        let items = DailyCheckInReminderScheduler.plannedItems(
            now: now,
            calendar: calendar,
            isTodayCompleted: true,
            todayDateKey: "2026-09-03",
            dateKeyForMoment: { date in
                Self.fixedDateKey(for: date, calendar: self.calendar)
            }
        )

        XCTAssertFalse(items.contains { $0.identifier == "daily-check-in:2026-09-03" })
        XCTAssertTrue(items.contains { $0.identifier == "daily-check-in:2026-09-04" })
    }

    func testPlannedItemsSchedulesWeekdayAt915Local() {
        let now = makeDate(year: 2026, month: 9, day: 3, hour: 8, minute: 0)
        let items = DailyCheckInReminderScheduler.plannedItems(
            now: now,
            calendar: calendar,
            isTodayCompleted: false,
            todayDateKey: "2026-09-03",
            dateKeyForMoment: { date in
                Self.fixedDateKey(for: date, calendar: self.calendar)
            }
        )

        guard let today = items.first(where: { $0.identifier == "daily-check-in:2026-09-03" }) else {
            return XCTFail("Expected today's reminder")
        }
        let components = calendar.dateComponents([.hour, .minute], from: today.fireDate)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 15)
    }

    func testPlannedItemsUsesDeterministicIdentifiers() {
        let now = makeDate(year: 2026, month: 9, day: 3, hour: 8, minute: 0)
        let items = DailyCheckInReminderScheduler.plannedItems(
            now: now,
            calendar: calendar,
            isTodayCompleted: false,
            todayDateKey: "2026-09-03",
            dateKeyForMoment: { date in
                Self.fixedDateKey(for: date, calendar: self.calendar)
            }
        )

        for item in items {
            XCTAssertTrue(item.identifier.hasPrefix(DailyCheckInReminderScheduler.identifierPrefix))
            XCTAssertEqual(item.identifier, DailyCheckInReminderScheduler.identifier(for: item.dateKey))
        }
    }

    func testPlannedItemsDoesNotDuplicateDateKeys() {
        let now = makeDate(year: 2026, month: 9, day: 3, hour: 8, minute: 0)
        let items = DailyCheckInReminderScheduler.plannedItems(
            now: now,
            calendar: calendar,
            isTodayCompleted: false,
            todayDateKey: "2026-09-03",
            dateKeyForMoment: { _ in "2026-09-03" }
        )

        let identifiers = items.map(\.identifier)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
        XCTAssertEqual(identifiers.count, 1)
    }

    func testPlannedItemsSkipsPastSameDayFireTime() {
        let now = makeDate(year: 2026, month: 9, day: 3, hour: 9, minute: 30)
        let items = DailyCheckInReminderScheduler.plannedItems(
            now: now,
            calendar: calendar,
            isTodayCompleted: false,
            todayDateKey: "2026-09-03",
            dateKeyForMoment: { date in
                Self.fixedDateKey(for: date, calendar: self.calendar)
            }
        )

        XCTAssertFalse(items.contains { $0.identifier == "daily-check-in:2026-09-03" })
    }

    func testPayloadParserMapsDailyCheckIn() {
        let destination = PushNotificationPayloadParser.parse(userInfo: [
            "type": "daily_check_in",
        ])
        XCTAssertEqual(destination.category, .dailyCheckIn)
    }

    func testNotificationRouterMapsDailyCheckInToSheet() {
        let destination = NotificationDestination(
            category: .dailyCheckIn,
            threadID: nil,
            tradeID: nil,
            postID: nil,
            reelID: nil,
            profileID: nil,
            conversationID: nil,
            roomID: nil,
            reportID: nil,
            rawUserInfo: ["type": "daily_check_in"]
        )
        XCTAssertEqual(NotificationRouter().destination(for: destination), .sheet(.dailyCheckIn))
    }

    @MainActor
    func testOpenDailyCheckInSheetSelectsHomeTab() {
        let store = NavigationStore(state: .initial)
        store.sessionPhase = .authenticated
        store.selectedTab = .profile
        let coordinator = NavigationCoordinator(store: store)

        coordinator.open(.sheet(.dailyCheckIn))

        XCTAssertEqual(store.selectedTab, .home)
        XCTAssertEqual(store.presentedSheet, .dailyCheckIn)
    }

    func testPreferencesDefaultEnabled() {
        let defaults = UserDefaults(suiteName: "DailyCheckInReminderTests")!
        defaults.removeObject(forKey: "tt.ios.dailyCheckInReminder.enabled")
        XCTAssertTrue(defaults.object(forKey: "tt.ios.dailyCheckInReminder.enabled") == nil)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }

    private static func fixedDateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
}
