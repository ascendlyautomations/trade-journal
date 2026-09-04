import SwiftUI

/// Semantic palette — features consume these names, never raw hex.
struct SemanticColorPalette: Sendable {
    // Brand / accent
    let accent: Color
    let accentMuted: Color
    let onAccent: Color

    // Backgrounds
    let backgroundPrimary: Color
    let backgroundSecondary: Color
    let backgroundGrouped: Color
    let backgroundElevated: Color

    // Surfaces
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let surfaceGrouped: Color
    let surfaceOverlay: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textQuaternary: Color
    let textInverse: Color

    // Separators / borders
    let separator: Color
    let border: Color
    let borderStrong: Color

    // Fill
    let fillPrimary: Color
    let fillSecondary: Color
    let fillTertiary: Color

    // Feedback
    let success: Color
    let warning: Color
    let error: Color
    let info: Color

    // Trading semantics
    let profit: Color
    let loss: Color
    let neutralMetric: Color

    // Accessibility-leaning high-contrast companions
    let accessibilityAccent: Color
    let accessibilityProfit: Color
    let accessibilityLoss: Color

    /// Adaptive System / default Experience palette.
    static let standard = SemanticColorPalette(
        accent: .experience(lightHex: 0x0A6E8A, darkHex: 0x4EC4E0),
        accentMuted: .experience(lightHex: 0x0A6E8A, darkHex: 0x4EC4E0, lightAlpha: 0.14, darkAlpha: 0.22),
        onAccent: .experience(lightHex: 0xFFFFFF, darkHex: 0x061018),

        backgroundPrimary: .experience(lightHex: 0xF5F7FA, darkHex: 0x0B1218),
        backgroundSecondary: .experience(lightHex: 0xFFFFFF, darkHex: 0x121A22),
        backgroundGrouped: .experience(lightHex: 0xEEF2F6, darkHex: 0x0B1218),
        backgroundElevated: .experience(lightHex: 0xFFFFFF, darkHex: 0x1A2430),

        surfacePrimary: .experience(lightHex: 0xFFFFFF, darkHex: 0x151E28),
        surfaceSecondary: .experience(lightHex: 0xF0F3F7, darkHex: 0x1C2733),
        surfaceGrouped: .experience(lightHex: 0xE8EEF4, darkHex: 0x121A22),
        surfaceOverlay: .experience(lightHex: 0x0B1218, darkHex: 0x000000, lightAlpha: 0.45, darkAlpha: 0.55),

        textPrimary: .experience(lightHex: 0x101820, darkHex: 0xF2F6FA),
        textSecondary: .experience(lightHex: 0x5B6775, darkHex: 0xA8B3BF),
        textTertiary: .experience(lightHex: 0x7E8B99, darkHex: 0x7E8B99),
        textQuaternary: .experience(lightHex: 0x9AA6B2, darkHex: 0x5C6772),
        textInverse: .experience(lightHex: 0xFFFFFF, darkHex: 0x0B1218),

        separator: .experience(lightHex: 0xD7DEE6, darkHex: 0x2A3542),
        border: .experience(lightHex: 0xD0D8E0, darkHex: 0x2F3B49),
        borderStrong: .experience(lightHex: 0xAAB6C2, darkHex: 0x445263),

        fillPrimary: .experience(lightHex: 0xE8EEF4, darkHex: 0x243140),
        fillSecondary: .experience(lightHex: 0xF0F3F7, darkHex: 0x1C2733),
        fillTertiary: .experience(lightHex: 0xF7F9FB, darkHex: 0x18222C),

        success: .experience(lightHex: 0x1F8A4C, darkHex: 0x3DDB84),
        warning: .experience(lightHex: 0xC47B00, darkHex: 0xFFC14D),
        error: .experience(lightHex: 0xC23131, darkHex: 0xFF6B6B),
        info: .experience(lightHex: 0x0A6E8A, darkHex: 0x4EC4E0),

        profit: .experience(lightHex: 0x148F4A, darkHex: 0x34D399),
        loss: .experience(lightHex: 0xC23030, darkHex: 0xF87171),
        neutralMetric: .experience(lightHex: 0x5B6775, darkHex: 0xA8B3BF),

        accessibilityAccent: .experience(lightHex: 0x065F7A, darkHex: 0x7DDBF0),
        accessibilityProfit: .experience(lightHex: 0x0B6B38, darkHex: 0x6EE7B7),
        accessibilityLoss: .experience(lightHex: 0x9F1D1D, darkHex: 0xFCA5A5)
    )
}

// MARK: - Theme Engine semantic aliases
extension SemanticColorPalette {
    var primaryBackground: Color { backgroundPrimary }
    var secondaryBackground: Color { backgroundSecondary }
    var groupedBackground: Color { backgroundGrouped }
    var navigationBackground: Color { backgroundSecondary }
    var tabBarBackground: Color { backgroundSecondary }
    var cardBackground: Color { surfacePrimary }
    var sheetBackground: Color { surfacePrimary }
    var toolbarBackground: Color { backgroundSecondary }

    var divider: Color { separator }

    var primaryText: Color { textPrimary }
    var secondaryText: Color { textSecondary }
    var tertiaryText: Color { textTertiary }

    var accentSecondary: Color { accentMuted }

    var positivePnL: Color { profit }
    var negativePnL: Color { loss }

    var overlay: Color { surfaceOverlay }
    var selection: Color { accentMuted }
    var highlight: Color { fillSecondary }
    var placeholder: Color { textTertiary }
    var skeleton: Color { fillPrimary }
    var disabled: Color { textQuaternary }
    var focus: Color { accent }

    /// Incoming DM / Trade Room bubble fill — slightly darker than the screen
    /// so bubbles separate cleanly (same family as segmented-control track / `fillPrimary`).
    var incomingMessageBubble: Color { fillPrimary }

    // MARK: - TradeTraxs promotion aliases (all themes map to semantic fields)

    /// App canvas — maps to ``backgroundPrimary``.
    var appBackground: Color { backgroundPrimary }

    /// Primary card / grouped surface — maps to ``surfacePrimary``.
    var surface: Color { surfacePrimary }

    /// Elevated card / row — maps to ``surfaceSecondary``.
    var elevatedSurface: Color { surfaceSecondary }

    /// Input and picker fills — maps to ``fillPrimary``.
    var inputSurface: Color { fillPrimary }

    /// Nested tertiary surface — maps to ``fillTertiary``.
    var secondarySurface: Color { fillTertiary }

    /// Selected / muted accent fill — maps to ``accentMuted``.
    var selectedSurface: Color { accentMuted }
}

/// Static facade — resolves through the active Theme Engine palette.
/// Prefer `@Environment(\.themeColors)` inside Views for live updates.
enum ExperienceColor {
    static var palette: SemanticColorPalette { ThemePaletteAnchor.current }

    static var accent: Color { palette.accent }
    static var accentMuted: Color { palette.accentMuted }
    static var onAccent: Color { palette.onAccent }

    static var backgroundPrimary: Color { palette.backgroundPrimary }
    static var backgroundSecondary: Color { palette.backgroundSecondary }
    static var backgroundGrouped: Color { palette.backgroundGrouped }
    static var backgroundElevated: Color { palette.backgroundElevated }

    static var surfacePrimary: Color { palette.surfacePrimary }
    static var surfaceSecondary: Color { palette.surfaceSecondary }
    static var surfaceGrouped: Color { palette.surfaceGrouped }
    static var surfaceOverlay: Color { palette.surfaceOverlay }

    static var textPrimary: Color { palette.textPrimary }
    static var textSecondary: Color { palette.textSecondary }
    static var textTertiary: Color { palette.textTertiary }
    static var textQuaternary: Color { palette.textQuaternary }
    static var textInverse: Color { palette.textInverse }

    static var separator: Color { palette.separator }
    static var border: Color { palette.border }
    static var borderStrong: Color { palette.borderStrong }

    static var fillPrimary: Color { palette.fillPrimary }
    static var fillSecondary: Color { palette.fillSecondary }
    static var fillTertiary: Color { palette.fillTertiary }
    static var incomingMessageBubble: Color { palette.incomingMessageBubble }

    static var success: Color { palette.success }
    static var warning: Color { palette.warning }
    static var error: Color { palette.error }
    static var info: Color { palette.info }

    static var profit: Color { palette.profit }
    static var loss: Color { palette.loss }
    static var neutralMetric: Color { palette.neutralMetric }

    /// PnL-aware color helper. Pair with sign / accessibility labels — never color alone.
    static func metric(_ value: Double, highContrast: Bool = false) -> Color {
        let colors = palette
        if value > 0 { return highContrast ? colors.accessibilityProfit : colors.profit }
        if value < 0 { return highContrast ? colors.accessibilityLoss : colors.loss }
        return colors.neutralMetric
    }

    static func metric(_ value: Double, palette: SemanticColorPalette, highContrast: Bool = false) -> Color {
        if value > 0 { return highContrast ? palette.accessibilityProfit : palette.profit }
        if value < 0 { return highContrast ? palette.accessibilityLoss : palette.loss }
        return palette.neutralMetric
    }
}
