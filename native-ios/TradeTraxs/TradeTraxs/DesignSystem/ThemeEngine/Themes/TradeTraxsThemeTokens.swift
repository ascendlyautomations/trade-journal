import SwiftUI

/// Canonical TradeTraxs appearance tokens — lighter muted-blue canvas, neutral gray
/// surfaces, and restrained cyan accent.
///
/// Consumed by ``ThemePalettes/tradeTraxsSignature``. System, Light, and Dark use
/// separate palettes and are unaffected.
enum TradeTraxsThemeTokens {
    // MARK: - Brand tokens

    /// Page, navigation, and grouped canvas.
    static let appBackground = Color(hex: 0x264058)

    /// Cards, grouped sections, and primary surfaces.
    static let surface = Color(hex: 0x383E47)

    /// Elevated rows and secondary surfaces.
    static let elevatedSurface = Color(hex: 0x424951)

    /// Inputs, pickers, and compact controls.
    static let inputSurface = elevatedSurface

    /// Subtle nested / tertiary surfaces.
    static let secondarySurface = Color(hex: 0x323840)

    /// High-contrast primary copy.
    static let primaryText = Color(hex: 0xF5F7FA)

    /// Labels, subtitles, and section headers.
    static let secondaryText = Color(hex: 0xB4BCC8)

    /// Placeholders and tertiary hints.
    static let tertiaryText = Color(hex: 0x8891A0)

    /// Row and section separators.
    static let divider = Color(hex: 0x505862)

    /// Subtle control outlines.
    static let border = Color(hex: 0x5A626D)

    /// TradeTraxs cyan/teal — interactive accent only.
    static let accent = Color(hex: 0x4EC4E0)

    /// Selected / muted accent fills.
    static let selectedSurface = accent.opacity(0.16)

    // MARK: - Semantic palette

    static var semanticPalette: SemanticColorPalette {
        SemanticColorPalette(
            accent: accent,
            accentMuted: selectedSurface,
            onAccent: Color(hex: 0x041018),
            backgroundPrimary: appBackground,
            backgroundSecondary: appBackground,
            backgroundGrouped: appBackground,
            backgroundElevated: Color(hex: 0x2E4A62),
            surfacePrimary: surface,
            surfaceSecondary: elevatedSurface,
            surfaceGrouped: surface,
            surfaceOverlay: Color(hex: 0x020812, alpha: 0.58),
            textPrimary: primaryText,
            textSecondary: secondaryText,
            textTertiary: tertiaryText,
            textQuaternary: Color(hex: 0x6E7785),
            textInverse: appBackground,
            separator: divider,
            border: border,
            borderStrong: Color(hex: 0x6A737F),
            fillPrimary: inputSurface,
            fillSecondary: surface,
            fillTertiary: secondarySurface,
            success: Color(hex: 0x34D399),
            warning: Color(hex: 0xE8B84A),
            error: Color(hex: 0xF87171),
            info: accent,
            profit: Color(hex: 0x34D399),
            loss: Color(hex: 0xF87171),
            neutralMetric: secondaryText,
            accessibilityAccent: Color(hex: 0x7DD3F0),
            accessibilityProfit: Color(hex: 0x6EE7B7),
            accessibilityLoss: Color(hex: 0xFCA5A5)
        )
    }
}

enum TradeTraxsFormSurfaceLayer {
    case surface
    case input

    func color(from colors: SemanticColorPalette) -> Color {
        switch self {
        case .surface: colors.surfacePrimary
        case .input: colors.fillPrimary
        }
    }
}
