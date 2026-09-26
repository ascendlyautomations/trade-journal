import Foundation

/// Stable theme keys. Built-ins ship with the app; custom IDs register at runtime.
struct ThemeIdentifier: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }

    static let system = ThemeIdentifier(rawValue: "system")
    static let light = ThemeIdentifier(rawValue: "light")
    static let dark = ThemeIdentifier(rawValue: "dark")

    /// Legacy persisted appearance — migrated to ``system`` on load.
    static let legacyTradeTraxsPersistedValue = "tradetraxs"

    var isBuiltIn: Bool {
        [.system, .light, .dark].contains(self)
    }
}
