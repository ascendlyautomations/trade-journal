import Foundation
import OSLog
import UserNotifications

/// Local daily check-in reminders — Mon–Fri 9:15 AM Eastern only.
enum DailyCheckInReminderScheduler {
    static let identifierPrefix = "daily-check-in:"

    static let reminderHour = 9
    static let reminderMinute = 15

    static let notificationTitle = "Complete your daily check-in!"
    static let notificationBody = "Take a minute to log how you're feeling before the market opens."

    static var plannedWeekdayRequests: [WeekdayEasternReminderSupport.PlannedRequest] {
        WeekdayEasternReminderSupport.plannedRequests(
            identifierPrefix: identifierPrefix,
            timeLabel: "0915",
            hour: reminderHour,
            minute: reminderMinute
        )
    }

    static var canonicalIdentifiers: [String] {
        plannedWeekdayRequests.map(\.identifier)
    }

    @MainActor
    static func sync(isEnabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { shouldRemove(identifier: $0) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }

        guard isEnabled else { return }

        for request in plannedWeekdayRequests {
            let content = UNMutableNotificationContent()
            content.title = notificationTitle
            content.body = notificationBody
            content.userInfo = ["type": "daily_check_in"]

            let components = WeekdayEasternReminderSupport.dateComponents(
                weekday: request.weekday,
                hour: request.hour,
                minute: request.minute
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let notification = UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(notification)
            } catch {
                AppLog.notifications.error(
                    "Daily check-in reminder schedule failed for \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Removes current and legacy date-keyed (`daily-check-in:YYYY-MM-DD`) pending requests.
    static func shouldRemove(identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    @MainActor
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { shouldRemove(identifier: $0) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
