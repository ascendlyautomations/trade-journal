import Foundation
import OSLog
import UserNotifications

struct DailyCheckInReminderScheduledItem: Equatable, Sendable {
    let identifier: String
    let dateKey: String
    let fireDate: Date
}

/// Pure planning + `UNUserNotificationCenter` application for weekday check-in reminders.
enum DailyCheckInReminderScheduler {
    static let identifierPrefix = "daily-check-in:"
    static let rollingCalendarDays = 14
    static let reminderHour = 9
    static let reminderMinute = 15

    static let notificationTitle = "Complete your daily check-in!"
    static let notificationBody = "Take a minute to log how you're feeling before the market opens."

    static func identifier(for dateKey: String) -> String {
        "\(identifierPrefix)\(dateKey)"
    }

    /// Builds upcoming Mon–Fri 9:15 AM local reminders keyed by authoritative Eastern check-in date.
    static func plannedItems(
        now: Date,
        calendar: Calendar,
        isTodayCompleted: Bool,
        todayDateKey: String,
        dateKeyForMoment: (Date) -> String = TraderPsychologyAnalyticsFoundation.todayCheckInDateKey
    ) -> [DailyCheckInReminderScheduledItem] {
        let startOfToday = calendar.startOfDay(for: now)
        var items: [DailyCheckInReminderScheduledItem] = []
        var seenIdentifiers = Set<String>()

        for dayOffset in 0..<rollingCalendarDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else {
                continue
            }
            guard isWeekday(day, calendar: calendar) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = reminderHour
            components.minute = reminderMinute
            components.second = 0
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            let dateKey = dateKeyForMoment(fireDate)
            if dateKey == todayDateKey, isTodayCompleted { continue }

            let identifier = identifier(for: dateKey)
            guard seenIdentifiers.insert(identifier).inserted else { continue }

            items.append(
                DailyCheckInReminderScheduledItem(
                    identifier: identifier,
                    dateKey: dateKey,
                    fireDate: fireDate
                )
            )
        }

        return items.sorted { $0.fireDate < $1.fireDate }
    }

    static func isWeekday(_ date: Date, calendar: Calendar) -> Bool {
        switch calendar.component(.weekday, from: date) {
        case 2...6:
            return true
        default:
            return false
        }
    }

    @MainActor
    static func sync(
        isEnabled: Bool,
        isTodayCompleted: Bool,
        todayDateKey: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }

        if !existingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existingIDs)
        }

        guard isEnabled else { return }

        let items = plannedItems(
            now: now,
            calendar: calendar,
            isTodayCompleted: isTodayCompleted,
            todayDateKey: todayDateKey
        )

        for item in items {
            let content = UNMutableNotificationContent()
            content.title = notificationTitle
            content.body = notificationBody
            content.userInfo = ["type": "daily_check_in"]

            let triggerComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: item.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: triggerComponents,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: item.identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                AppLog.notifications.error(
                    "Daily check-in reminder schedule failed for \(item.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    @MainActor
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
