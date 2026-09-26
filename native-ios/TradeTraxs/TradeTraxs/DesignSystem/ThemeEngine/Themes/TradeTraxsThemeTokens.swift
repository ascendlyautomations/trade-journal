import SwiftUI

/// Form surface layering helper (standard System / Light / Dark palettes).
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
