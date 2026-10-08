import Foundation
import OSLog
import UserNotifications

/// Local trade-import reminders — Mon–Fri 11:15 AM and 4:00 PM Eastern only.
enum TradeImportReminderScheduler {
    static let identifierPrefix = "trade-import-reminder:"

    /// Legacy daily-repeat identifiers (removed on sync).
    static let legacyIdentifiers = [
        "trade-import-reminder:1115-et",
        "trade-import-reminder:1600-et",
    ]

    static let notificationType = "trade_import_reminder"

    static let notificationTitle = "Traded today?"
    static let notificationBody =
        "Don't forget to log your trades! Import them into TradeTraxs to keep your journal up to date."

    private static let morningHour = 11
    private static let morningMinute = 15
    private static let afternoonHour = 16
    private static let afternoonMinute = 0

    static var plannedWeekdayRequests: [WeekdayEasternReminderSupport.PlannedRequest] {
        WeekdayEasternReminderSupport.plannedRequests(
            identifierPrefix: identifierPrefix,
            timeLabel: "1115",
            hour: morningHour,
            minute: morningMinute
        )
        + WeekdayEasternReminderSupport.plannedRequests(
            identifierPrefix: identifierPrefix,
            timeLabel: "1600",
            hour: afternoonHour,
            minute: afternoonMinute
        )
    }

    static var canonicalIdentifiers: [String] {
        plannedWeekdayRequests.map(\.identifier)
    }

    @MainActor
    static func sync(isEnabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let pendingIDSet = Set(pending.map(\.identifier))
        var removeIDs: [String] = pendingIDSet.filter { shouldRemove(identifier: $0) }
        for legacy in legacyIdentifiers where pendingIDSet.contains(legacy) {
            removeIDs.append(legacy)
        }
        removeIDs = Array(Set(removeIDs))
        if !removeIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: removeIDs)
        }

        guard isEnabled else { return }

        for request in plannedWeekdayRequests {
            let content = UNMutableNotificationContent()
            content.title = notificationTitle
            content.body = notificationBody
            content.sound = .default
            content.userInfo = ["type": notificationType]

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
                    "Trade import reminder schedule failed for \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    static func shouldRemove(identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    @MainActor
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { shouldRemove(identifier: $0) }
        var all = Set(ids)
        all.formUnion(legacyIdentifiers)
        guard !all.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: Array(all))
    }
}
