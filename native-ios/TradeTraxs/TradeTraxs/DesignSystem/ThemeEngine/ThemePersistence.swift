import Foundation

protocol ThemePersisting: Sendable {
    func loadSelectedTheme() -> ThemeIdentifier?
    func saveSelectedTheme(_ identifier: ThemeIdentifier)
}

struct UserDefaultsThemePersistence: ThemePersisting {
    private let key: String
    private let defaults: UserDefaults

    init(key: String = "theme.selectedIdentifier", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func loadSelectedTheme() -> ThemeIdentifier? {
        guard let raw = defaults.string(forKey: key), !raw.isEmpty else { return nil }
        return ThemeIdentifier(rawValue: raw)
    }

    func saveSelectedTheme(_ identifier: ThemeIdentifier) {
        defaults.set(identifier.rawValue, forKey: key)
    }
}
