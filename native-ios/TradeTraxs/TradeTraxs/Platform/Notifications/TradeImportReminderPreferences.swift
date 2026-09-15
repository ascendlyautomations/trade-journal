import Foundation

/// Device-local preference for weekday trade-import reminders (11:15 AM / 4:00 PM Eastern).
enum TradeImportReminderPreferences {
    private static let enabledKey = "tt.ios.tradeImportReminder.enabled"

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
