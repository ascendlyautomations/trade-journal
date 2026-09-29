import XCTest
@testable import TradeTraxs

final class DailyCheckInReminderTests: XCTestCase {
    func testPlannedWeekdayRequestsCountAndTimes() {
        let requests = DailyCheckInReminderScheduler.plannedWeekdayRequests
        XCTAssertEqual(requests.count, 5)

        for request in requests {
            XCTAssertEqual(request.hour, 9)
            XCTAssertEqual(request.minute, 15)
            XCTAssertTrue(WeekdayEasternReminderSupport.weekdayRange.contains(request.weekday))
            XCTAssertEqual(request.timeZone, WeekdayEasternReminderSupport.easternTimeZone)
        }
    }

    func testPlannedWeekdayRequestsNoWeekend() {
        let weekdays = Set(DailyCheckInReminderScheduler.plannedWeekdayRequests.map(\.weekday))
        XCTAssertEqual(weekdays, Set([2, 3, 4, 5, 6]))
        XCTAssertFalse(weekdays.contains(1))
        XCTAssertFalse(weekdays.contains(7))
    }

    func testCanonicalIdentifiersStable() {
        let ids = DailyCheckInReminderScheduler.canonicalIdentifiers
        XCTAssertEqual(ids.count, 5)
        XCTAssertEqual(ids, [
            "daily-check-in:0915:wd2",
            "daily-check-in:0915:wd3",
            "daily-check-in:0915:wd4",
            "daily-check-in:0915:wd5",
            "daily-check-in:0915:wd6",
        ])
    }

    func testDateComponentsUseAmericaNewYork() {
        let request = DailyCheckInReminderScheduler.plannedWeekdayRequests[0]
        let components = WeekdayEasternReminderSupport.dateComponents(
            weekday: request.weekday,
            hour: request.hour,
            minute: request.minute
        )
        XCTAssertEqual(components.timeZone, TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(components.weekday, request.weekday)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 15)
    }

    func testShouldRemoveLegacyDateKeyedIdentifiers() {
        XCTAssertTrue(DailyCheckInReminderScheduler.shouldRemove(identifier: "daily-check-in:2026-09-03"))
        XCTAssertTrue(DailyCheckInReminderScheduler.shouldRemove(identifier: "daily-check-in:0915:wd2"))
        XCTAssertFalse(DailyCheckInReminderScheduler.shouldRemove(identifier: "trade-import-reminder:1115:wd2"))
        XCTAssertFalse(DailyCheckInReminderScheduler.shouldRemove(identifier: "push:activity:123"))
    }

    func testRescheduleUsesStableCanonicalSet() {
        let first = Set(DailyCheckInReminderScheduler.canonicalIdentifiers)
        let second = Set(DailyCheckInReminderScheduler.canonicalIdentifiers)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 5)
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
}
