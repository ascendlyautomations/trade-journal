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
        detail: "Match Light or Dark with iOS",
        isPremiumSignature: false,
        supportsSystemAppearanceFollow: true
    )

    static let light = ThemeMetadata(
        identifier: .light,
        displayName: "Light",
        detail: "Always use the light appearance",
        isPremiumSignature: false,
        supportsSystemAppearanceFollow: false
    )

    static let dark = ThemeMetadata(
        identifier: .dark,
        displayName: "Dark",
        detail: "Always use the dark appearance",
        isPremiumSignature: false,
        supportsSystemAppearanceFollow: false
    )

    static let tradeTraxs = ThemeMetadata(
        identifier: .tradeTraxs,
        displayName: "TradeTraxs",
        detail: "Brand navy surfaces with cyan accents",
        isPremiumSignature: true,
        supportsSystemAppearanceFollow: false
    )
}
