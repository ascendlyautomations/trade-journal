import Foundation
import Observation
import SwiftUI

/// Owns selection, persistence, and resolution of the active theme.
///
/// Not `@MainActor`-isolated — matches ``NavigationEnvironment`` so storing this
/// in ``AppEnvironment`` does not poison SwiftUI `EnvironmentKey` / key-path types.
@Observable
final class ThemeManager {
    private let persistence: any ThemePersisting
    private let resolver: ThemeResolver
    private let configuration: ThemeConfiguration

    private(set) var selectedIdentifier: ThemeIdentifier
    /// Interface style from the system (updated by the root view).
    var interfaceStyle: ColorScheme = .dark

    init(
        persistence: any ThemePersisting = UserDefaultsThemePersistence(),
        registry: ThemeRegistry = ThemeRegistry(),
        configuration: ThemeConfiguration = .default
    ) {
        self.persistence = persistence
        self.resolver = ThemeResolver(registry: registry, configuration: configuration)
        self.configuration = configuration
        let loaded = persistence.loadSelectedTheme() ?? configuration.defaultTheme
        let normalized = Self.normalizePersistedTheme(loaded, registry: registry)
        self.selectedIdentifier = normalized
        if normalized != loaded {
            persistence.saveSelectedTheme(normalized)
        }
        publishAnchor()
    }

    /// Maps legacy / unknown persisted values to a supported built-in theme.
    private static func normalizePersistedTheme(
        _ identifier: ThemeIdentifier,
        registry: ThemeRegistry
    ) -> ThemeIdentifier {
        if identifier.rawValue == ThemeIdentifier.legacyTradeTraxsPersistedValue {
            return .system
        }
        if registry.theme(for: identifier) != nil {
            return identifier
        }
        return .system
    }

    var registry: ThemeRegistry { resolver.registry }

    var activeTheme: any AppThemeProtocol {
        resolver.theme(for: selectedIdentifier)
    }

    var preferredColorScheme: ColorScheme? {
        resolver.preferredColorScheme(for: selectedIdentifier)
    }

    var colors: SemanticColorPalette {
        resolver.palette(for: selectedIdentifier, interfaceStyle: interfaceStyle)
    }

    var themeEnvironment: ThemeEnvironment {
        let colors = colors
        return ThemeEnvironment(
            identifier: selectedIdentifier,
            colors: colors,
            preferredColorScheme: preferredColorScheme,
            experienceTheme: ExperienceTheme(
                colors: colors,
                prefersHighContrastMetrics: false
            ),
            metadata: activeTheme.metadata
        )
    }

    var appearanceSettings: AppearanceSettingsModel {
        AppearanceSettingsModel.make(selected: selectedIdentifier, registry: registry)
    }

    func select(
        _ identifier: ThemeIdentifier,
        reduceMotion: Bool = false
    ) {
        guard registry.theme(for: identifier) != nil else { return }
        ThemeTransition.perform(
            reduceMotion: reduceMotion,
            animates: configuration.animatesTransitions
        ) {
            selectedIdentifier = identifier
            persistence.saveSelectedTheme(identifier)
            publishAnchor()
        }
    }

    func updateInterfaceStyle(_ style: ColorScheme) {
        guard interfaceStyle != style else { return }
        interfaceStyle = style
        publishAnchor()
    }

    private func publishAnchor() {
        ThemePaletteAnchor.current = colors
    }
}
