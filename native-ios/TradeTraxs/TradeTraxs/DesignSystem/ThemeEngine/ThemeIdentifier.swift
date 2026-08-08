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
    static let tradeTraxs = ThemeIdentifier(rawValue: "tradetraxs")

    var isBuiltIn: Bool {
        [.system, .light, .dark, .tradeTraxs].contains(self)
    }
}
