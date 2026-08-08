import SwiftUI

/// Environment payload for the active theme. Components read semantic colors from here.
struct ThemeEnvironment: Sendable {
    var identifier: ThemeIdentifier
    var colors: SemanticColorPalette
    var preferredColorScheme: ColorScheme?
    var experienceTheme: ExperienceTheme
    var metadata: ThemeMetadata

    static let fallback = ThemeEnvironment(
        identifier: .system,
        colors: .standard,
        preferredColorScheme: nil,
        experienceTheme: .standard,
        metadata: .system
    )
}

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ThemeEnvironment.fallback
}

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue = SemanticColorPalette.standard
}

extension EnvironmentValues {
    var themeEnvironment: ThemeEnvironment {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }

    /// Semantic colors for the active theme — preferred API for Experience components.
    var themeColors: SemanticColorPalette {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}

extension View {
    /// Injects ThemeEnvironment + ExperienceTheme + color scheme + tint in one place.
    func applyThemeEnvironment(_ environment: ThemeEnvironment) -> some View {
        self
            .environment(\.themeEnvironment, environment)
            .environment(\.themeColors, environment.colors)
            .experienceTheme(environment.experienceTheme)
            .preferredColorScheme(environment.preferredColorScheme)
            .tint(environment.colors.accent)
    }
}
