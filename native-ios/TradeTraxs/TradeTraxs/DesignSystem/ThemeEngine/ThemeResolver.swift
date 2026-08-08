import Foundation
import SwiftUI

/// Resolves an identifier + interface style into a concrete palette / color scheme.
struct ThemeResolver: Sendable {
    let registry: ThemeRegistry
    let configuration: ThemeConfiguration

    init(registry: ThemeRegistry = ThemeRegistry(), configuration: ThemeConfiguration = .default) {
        self.registry = registry
        self.configuration = configuration
    }

    func theme(for identifier: ThemeIdentifier) -> any AppThemeProtocol {
        if let theme = registry.theme(for: identifier) {
            return theme
        }
        return registry.theme(for: configuration.defaultTheme) ?? SystemTheme()
    }

    func preferredColorScheme(for identifier: ThemeIdentifier) -> ColorScheme? {
        theme(for: identifier).colorSchemeOverride
    }

    func palette(
        for identifier: ThemeIdentifier,
        interfaceStyle: ColorScheme
    ) -> SemanticColorPalette {
        let theme = theme(for: identifier)
        // Fixed themes ignore the passed interface style's adaptivity by returning a constant palette.
        if let override = theme.colorSchemeOverride {
            return theme.palette(for: override)
        }
        return theme.palette(for: interfaceStyle)
    }
}

/// Process-wide palette mirror for non-View helpers (`ExperienceColor`, `BannerTone`).
enum ThemePaletteAnchor: Sendable {
    nonisolated(unsafe) static var current: SemanticColorPalette = .standard
}
