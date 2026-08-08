import SwiftUI

/// Bundled Experience System configuration for environment injection.
struct ExperienceTheme: Sendable {
    var colors: SemanticColorPalette
    var prefersHighContrastMetrics: Bool

    static let standard = ExperienceTheme(
        colors: .standard,
        prefersHighContrastMetrics: false
    )

    func metricColor(for value: Double) -> Color {
        ExperienceColor.metric(
            value,
            palette: colors,
            highContrast: prefersHighContrastMetrics
        )
    }
}

private struct ExperienceThemeKey: EnvironmentKey {
    static let defaultValue = ExperienceTheme.standard
}

extension EnvironmentValues {
    var experienceTheme: ExperienceTheme {
        get { self[ExperienceThemeKey.self] }
        set { self[ExperienceThemeKey.self] = newValue }
    }
}

extension View {
    func experienceTheme(_ theme: ExperienceTheme = .standard) -> some View {
        environment(\.experienceTheme, theme)
    }
}
