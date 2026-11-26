import XCTest
@testable import TradeTraxs

final class PerformanceReportReminderTests: XCTestCase {
    func testCanonicalIdentifiersAreStable() {
        let first = Set(PerformanceReportReminderScheduler.canonicalIdentifiers)
        let second = Set(PerformanceReportReminderScheduler.canonicalIdentifiers)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 2)
    }

    func testShouldRemoveOnlyPerformanceReportPrefix() {
        XCTAssertTrue(PerformanceReportReminderScheduler.shouldRemove(identifier: PerformanceReportReminderScheduler.weeklyIdentifier))
        XCTAssertFalse(PerformanceReportReminderScheduler.shouldRemove(identifier: "daily-check-in:0915:wd2"))
        XCTAssertFalse(PerformanceReportReminderScheduler.shouldRemove(identifier: "push:activity:123"))
        XCTAssertTrue(
            PerformanceReportReminderScheduler.isDebugProbeIdentifier(
                "performance-report:debug:weekly"
            )
        )
    }

    func testWeeklyResolutionOnSaturdayUsesCurrentWeekMonday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 11, day: 14, hour: 13)
        let saturday = try XCTUnwrap(calendar.date(from: components))

        let reportID = PerformanceReportReminderPeriodResolution.resolvedReportID(
            kind: .weekly,
            referenceDate: saturday
        )
        XCTAssertEqual(reportID.rawValue, "week:2026-11-09")
    }

    func testMonthlyResolutionOnFirstUsesPriorMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 7, day: 1, hour: 13)
        let firstOfMonth = try XCTUnwrap(calendar.date(from: components))

        let reportID = PerformanceReportReminderPeriodResolution.resolvedReportID(
            kind: .monthly,
            referenceDate: firstOfMonth
        )
        XCTAssertEqual(reportID.rawValue, "month:2026-06")
    }

    func testParserUsesDeliveryDateNotTapDateForWeekly() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let saturdayComponents = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 11,
            day: 14,
            hour: 13
        )
        let saturday = try XCTUnwrap(calendar.date(from: saturdayComponents))
        let mondayAfter = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: saturday))

        let atDelivery = PerformanceReportReminderPeriodResolution.resolvedReportID(
            kind: .weekly,
            referenceDate: saturday
        )
        let ifTappedLater = PerformanceReportReminderPeriodResolution.resolvedReportID(
            kind: .weekly,
            referenceDate: mondayAfter
        )
        XCTAssertNotEqual(atDelivery, ifTappedLater)

        let destination = PushNotificationPayloadParser.parse(
            userInfo: [
                "type": "trading_report",
                PerformanceReportReminderPeriodResolution.userInfoKey: "weekly",
            ],
            deliveryDate: saturday
        )
        XCTAssertEqual(destination.reportID, atDelivery)
    }

    func testPayloadParserResolvesLocalWeeklyReminder() {
        let destination = PushNotificationPayloadParser.parse(userInfo: [
            "type": "trading_report",
            PerformanceReportReminderPeriodResolution.userInfoKey: "weekly",
        ])
        XCTAssertEqual(destination.category, .tradingReport)
        XCTAssertNotNil(destination.reportID)
        XCTAssertEqual(destination.reportID?.rawValue.hasPrefix("week:"), true)
    }

    func testPayloadParserResolvesLocalMonthlyReminder() {
        let destination = PushNotificationPayloadParser.parse(userInfo: [
            "type": "trading_report",
            PerformanceReportReminderPeriodResolution.userInfoKey: "monthly",
        ])
        XCTAssertEqual(destination.category, .tradingReport)
        XCTAssertNotNil(destination.reportID)
        XCTAssertEqual(destination.reportID?.rawValue.hasPrefix("month:"), true)
    }

    func testNotificationRouterMapsTradingReportToHomeReport() {
        let reportID = ReportID("week:2026-11-09")
        let destination = NotificationDestination(
            category: .tradingReport,
            threadID: nil,
            tradeID: nil,
            postID: nil,
            reelID: nil,
            profileID: nil,
            conversationID: nil,
            roomID: nil,
            reportID: reportID,
            rawUserInfo: [
                "type": "trading_report",
                PerformanceReportReminderPeriodResolution.userInfoKey: "weekly",
            ]
        )
        XCTAssertEqual(NotificationRouter().destination(for: destination), .home(.report(reportID)))
    }
}