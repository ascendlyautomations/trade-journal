import Foundation

/// Device-local preference for weekday daily check-in reminders (9:15 AM local).
enum DailyCheckInReminderPreferences {
    private static let enabledKey = "tt.ios.dailyCheckInReminder.enabled"

    /// Defaults to `true` when unset — opt-out per device.
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }
}
