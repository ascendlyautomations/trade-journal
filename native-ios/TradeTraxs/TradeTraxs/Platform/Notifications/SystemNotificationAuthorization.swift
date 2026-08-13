import Foundation
import OSLog
import UserNotifications

/// iOS system notification permission — never confuse with in-app preference toggles.
enum SystemNotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var isEnabled: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        }
    }

    var settingsLabel: String {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return "On"
        case .denied, .notDetermined:
            return "Off"
        }
    }

    static func from(_ status: UNAuthorizationStatus) -> SystemNotificationAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .denied
        }
    }
}

enum SystemNotificationAuthorization {
    static func currentStatus() async -> SystemNotificationAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return .from(settings.authorizationStatus)
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
        } catch {
            AppLog.notifications.error(
                "Notification authorization failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
