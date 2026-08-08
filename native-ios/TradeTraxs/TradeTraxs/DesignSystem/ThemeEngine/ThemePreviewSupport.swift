import SwiftUI

/// Helpers for SwiftUI previews / future Settings swatches — not feature UI.
enum ThemePreviewSupport {
    static func swatchColors(for palette: SemanticColorPalette) -> [Color] {
        [
            palette.backgroundPrimary,
            palette.surfacePrimary,
            palette.accent,
            palette.positivePnL,
            palette.negativePnL,
            palette.textPrimary,
        ]
    }

    static func previewPalette(identifier: ThemeIdentifier) -> SemanticColorPalette {
        ThemeResolver().palette(for: identifier, interfaceStyle: .dark)
    }
}
