import SwiftUI

/// Contract every plug-and-play theme must satisfy.
///
/// Themes define semantic meaning only — never layout, typography, or feature chrome.
protocol AppThemeProtocol: Sendable {
    var metadata: ThemeMetadata { get }

    /// Fixed override for `preferredColorScheme`. `nil` means follow the system.
    var colorSchemeOverride: ColorScheme? { get }

    /// Resolved semantic palette for the active interface style.
    func palette(for colorScheme: ColorScheme) -> SemanticColorPalette
}

typealias ThemeProtocol = AppThemeProtocol
