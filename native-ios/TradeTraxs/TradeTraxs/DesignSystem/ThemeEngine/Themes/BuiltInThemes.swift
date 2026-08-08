import SwiftUI

struct SystemTheme: AppThemeProtocol {
    var metadata: ThemeMetadata { .system }
    var colorSchemeOverride: ColorScheme? { nil }

    func palette(for colorScheme: ColorScheme) -> SemanticColorPalette {
        _ = colorScheme
        return ThemePalettes.adaptiveStandard
    }
}

struct LightTheme: AppThemeProtocol {
    var metadata: ThemeMetadata { .light }
    var colorSchemeOverride: ColorScheme? { .light }

    func palette(for colorScheme: ColorScheme) -> SemanticColorPalette {
        _ = colorScheme
        return ThemePalettes.lightFixed
    }
}

struct DarkTheme: AppThemeProtocol {
    var metadata: ThemeMetadata { .dark }
    var colorSchemeOverride: ColorScheme? { .dark }

    func palette(for colorScheme: ColorScheme) -> SemanticColorPalette {
        _ = colorScheme
        return ThemePalettes.darkFixed
    }
}

struct TradeTraxsTheme: AppThemeProtocol {
    var metadata: ThemeMetadata { .tradeTraxs }
    /// Signature look stays fixed regardless of system light/dark.
    var colorSchemeOverride: ColorScheme? { .dark }

    func palette(for colorScheme: ColorScheme) -> SemanticColorPalette {
        _ = colorScheme
        return ThemePalettes.tradeTraxsSignature
    }
}
