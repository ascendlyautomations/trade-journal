import Foundation

/// Mon–Fri local notification planning in ``America/New_York`` (DST-aware via `DateComponents.timeZone`).
enum WeekdayEasternReminderSupport {
    static let easternTimeZone = TimeZone(identifier: "America/New_York")!

    /// `Calendar` weekday: Sunday = 1 … Saturday = 7.
    static let weekdayRange = 2...6

    struct PlannedRequest: Equatable, Sendable {
        var identifier: String
        var weekday: Int
        var hour: Int
        var minute: Int
        var timeZone: TimeZone
    }

    static func dateComponents(weekday: Int, hour: Int, minute: Int) -> DateComponents {
        var components = DateComponents()
        components.timeZone = easternTimeZone
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        return components
    }

    static func plannedRequests(
        identifierPrefix: String,
        timeLabel: String,
        hour: Int,
        minute: Int
    ) -> [PlannedRequest] {
        weekdayRange.map { weekday in
            PlannedRequest(
                identifier: "\(identifierPrefix)\(timeLabel):wd\(weekday)",
                weekday: weekday,
                hour: hour,
                minute: minute,
                timeZone: easternTimeZone
            )
        }
    }
}
