import Foundation

/// Device-local preference for weekday trade-import reminders (11:15 AM / 4:00 PM Eastern).
enum TradeImportReminderPreferences {
    private static let enabledKey = "tt.ios.tradeImportReminder.enabled"

    /// Unset means “follow iOS permission default” until ``applyDefaultIfNeeded`` runs.
    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else {
                return false
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    /// Default ON once the user has granted TradeTraxs notification permission.
    static func applyDefaultIfNeeded(authorizationGranted: Bool) {
        guard UserDefaults.standard.object(forKey: enabledKey) == nil else { return }
        guard authorizationGranted else { return }
        UserDefaults.standard.set(true, forKey: enabledKey)
    }
}
