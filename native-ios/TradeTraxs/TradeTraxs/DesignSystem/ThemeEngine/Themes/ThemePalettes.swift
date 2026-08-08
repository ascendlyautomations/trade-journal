import SwiftUI

/// Shared palette factories for built-in themes.
enum ThemePalettes {
    /// Adaptive System palette (current Experience standard).
    static let adaptiveStandard = SemanticColorPalette.standard

    /// Fixed Light — always light tokens.
    static let lightFixed = SemanticColorPalette(
        accent: Color(hex: 0x0A6E8A),
        accentMuted: Color(hex: 0x0A6E8A, alpha: 0.14),
        onAccent: Color(hex: 0xFFFFFF),
        backgroundPrimary: Color(hex: 0xF5F7FA),
        backgroundSecondary: Color(hex: 0xFFFFFF),
        backgroundGrouped: Color(hex: 0xEEF2F6),
        backgroundElevated: Color(hex: 0xFFFFFF),
        surfacePrimary: Color(hex: 0xFFFFFF),
        surfaceSecondary: Color(hex: 0xF0F3F7),
        surfaceGrouped: Color(hex: 0xE8EEF4),
        surfaceOverlay: Color(hex: 0x0B1218, alpha: 0.45),
        textPrimary: Color(hex: 0x101820),
        textSecondary: Color(hex: 0x5B6775),
        textTertiary: Color(hex: 0x7E8B99),
        textQuaternary: Color(hex: 0x9AA6B2),
        textInverse: Color(hex: 0xFFFFFF),
        separator: Color(hex: 0xD7DEE6),
        border: Color(hex: 0xD0D8E0),
        borderStrong: Color(hex: 0xAAB6C2),
        fillPrimary: Color(hex: 0xE8EEF4),
        fillSecondary: Color(hex: 0xF0F3F7),
        fillTertiary: Color(hex: 0xF7F9FB),
        success: Color(hex: 0x1F8A4C),
        warning: Color(hex: 0xC47B00),
        error: Color(hex: 0xC23131),
        info: Color(hex: 0x0A6E8A),
        profit: Color(hex: 0x148F4A),
        loss: Color(hex: 0xC23030),
        neutralMetric: Color(hex: 0x5B6775),
        accessibilityAccent: Color(hex: 0x065F7A),
        accessibilityProfit: Color(hex: 0x0B6B38),
        accessibilityLoss: Color(hex: 0x9F1D1D)
    )

    /// Fixed Dark — always dark tokens.
    static let darkFixed = SemanticColorPalette(
        accent: Color(hex: 0x4EC4E0),
        accentMuted: Color(hex: 0x4EC4E0, alpha: 0.22),
        onAccent: Color(hex: 0x061018),
        backgroundPrimary: Color(hex: 0x0B1218),
        backgroundSecondary: Color(hex: 0x121A22),
        backgroundGrouped: Color(hex: 0x0B1218),
        backgroundElevated: Color(hex: 0x1A2430),
        surfacePrimary: Color(hex: 0x151E28),
        surfaceSecondary: Color(hex: 0x1C2733),
        surfaceGrouped: Color(hex: 0x121A22),
        surfaceOverlay: Color(hex: 0x000000, alpha: 0.55),
        textPrimary: Color(hex: 0xF2F6FA),
        textSecondary: Color(hex: 0xA8B3BF),
        textTertiary: Color(hex: 0x7E8B99),
        textQuaternary: Color(hex: 0x5C6772),
        textInverse: Color(hex: 0x0B1218),
        separator: Color(hex: 0x2A3542),
        border: Color(hex: 0x2F3B49),
        borderStrong: Color(hex: 0x445263),
        fillPrimary: Color(hex: 0x243140),
        fillSecondary: Color(hex: 0x1C2733),
        fillTertiary: Color(hex: 0x18222C),
        success: Color(hex: 0x3DDB84),
        warning: Color(hex: 0xFFC14D),
        error: Color(hex: 0xFF6B6B),
        info: Color(hex: 0x4EC4E0),
        profit: Color(hex: 0x34D399),
        loss: Color(hex: 0xF87171),
        neutralMetric: Color(hex: 0xA8B3BF),
        accessibilityAccent: Color(hex: 0x7DDBF0),
        accessibilityProfit: Color(hex: 0x6EE7B7),
        accessibilityLoss: Color(hex: 0xFCA5A5)
    )

    /// Signature TradeTraxs — premium fixed look (Wallet / Fitness / Stocks inspired).
    /// Deep graphite canvas, soft card lift, restrained teal accent — not a blue wash.
    static let tradeTraxsSignature = SemanticColorPalette(
        accent: Color(hex: 0x3DB8C9),
        accentMuted: Color(hex: 0x3DB8C9, alpha: 0.18),
        onAccent: Color(hex: 0x041016),
        backgroundPrimary: Color(hex: 0x0E141A),
        backgroundSecondary: Color(hex: 0x151C24),
        backgroundGrouped: Color(hex: 0x0E141A),
        backgroundElevated: Color(hex: 0x1C2530),
        surfacePrimary: Color(hex: 0x182128),
        surfaceSecondary: Color(hex: 0x1F2A33),
        surfaceGrouped: Color(hex: 0x151C24),
        surfaceOverlay: Color(hex: 0x020507, alpha: 0.62),
        textPrimary: Color(hex: 0xF4F7FA),
        textSecondary: Color(hex: 0x9AA8B5),
        textTertiary: Color(hex: 0x738190),
        textQuaternary: Color(hex: 0x556270),
        textInverse: Color(hex: 0x0E141A),
        separator: Color(hex: 0x2A343E),
        border: Color(hex: 0x313C47),
        borderStrong: Color(hex: 0x4A5866),
        fillPrimary: Color(hex: 0x24303A),
        fillSecondary: Color(hex: 0x1F2A33),
        fillTertiary: Color(hex: 0x1A242C),
        success: Color(hex: 0x3DDB84),
        warning: Color(hex: 0xE8B84A),
        error: Color(hex: 0xF07178),
        info: Color(hex: 0x5EC9D6),
        profit: Color(hex: 0x3DDB84),
        loss: Color(hex: 0xF07178),
        neutralMetric: Color(hex: 0x9AA8B5),
        accessibilityAccent: Color(hex: 0x7ADCE8),
        accessibilityProfit: Color(hex: 0x6EE7B7),
        accessibilityLoss: Color(hex: 0xFCA5A5)
    )
}

extension Color {
    /// Fixed (non-adaptive) hex color for theme palettes.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
