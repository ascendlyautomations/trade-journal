import Foundation

/// Descriptive metadata for pickers / Settings — never visual tokens.
struct ThemeMetadata: Hashable, Sendable, Identifiable {
    var id: ThemeIdentifier { identifier }
    var identifier: ThemeIdentifier
    var displayName: String
    var detail: String
    var isPremiumSignature: Bool
    var supportsSystemAppearanceFollow: Bool

    static let system = ThemeMetadata(
        identifier: .system,
        displayName: "System",
        detail: "Follows your iPhone appearance",
        isPremiumSignature: false,
        supportsSystemAppearanceFollow: true
    )

    static let light = ThemeMetadata(
        identifier: .light,
        displayName: "Light",
        detail: "Always use Light Mode",
        isPremiumSignature: false,
        supportsSystemAppearanceFollow: false
    )

    static let dark = ThemeMetadata(
        identifier: .dark,
        displayName: "Dark",
        detail: "Always use Dark Mode",
        isPremiumSignature: false,
        supportsSystemAppearanceFollow: false
    )
}
