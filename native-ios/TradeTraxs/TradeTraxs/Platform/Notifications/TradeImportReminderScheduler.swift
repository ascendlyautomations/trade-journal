import Foundation
import OSLog
import UserNotifications

/// Local daily trade-import reminders at fixed Eastern times (DST-aware).
enum TradeImportReminderScheduler {
    static let morningIdentifier = "trade-import-reminder:1115-et"
    static let afternoonIdentifier = "trade-import-reminder:1600-et"
    static let identifierPrefix = "trade-import-reminder:"

    static let notificationType = "trade_import_reminder"

    static let easternTimeZone = TimeZone(identifier: "America/New_York")!

    static let morningTitle = "TradeTraxs"
    static let morningBody = "Made any trades today? Don't forget to add or import them."

    static let afternoonTitle = "TradeTraxs"
    static let afternoonBody = "Import your trades today and keep your journal up to date."

    struct Slot: Equatable, Sendable {
        var identifier: String
        var hour: Int
        var minute: Int
        var title: String
        var body: String
    }

    static let slots: [Slot] = [
        Slot(
            identifier: morningIdentifier,
            hour: 11,
            minute: 15,
            title: morningTitle,
            body: morningBody
        ),
        Slot(
            identifier: afternoonIdentifier,
            hour: 16,
            minute: 0,
            title: afternoonTitle,
            body: afternoonBody
        ),
    ]

    static var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = easternTimeZone
        return calendar
    }

    @MainActor
    static func sync(isEnabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }

        if !existingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existingIDs)
        }

        guard isEnabled else { return }

        let calendar = easternCalendar
        for slot in slots {
            var components = DateComponents()
            components.timeZone = easternTimeZone
            components.hour = slot.hour
            components.minute = slot.minute

            let content = UNMutableNotificationContent()
            content.title = slot.title
            content.body = slot.body
            content.userInfo = ["type": notificationType]

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: slot.identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                AppLog.notifications.error(
                    "Trade import reminder schedule failed for \(slot.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
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
