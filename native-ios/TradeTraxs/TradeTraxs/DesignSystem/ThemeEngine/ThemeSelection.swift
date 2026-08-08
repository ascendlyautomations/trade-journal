import Foundation

/// Row model for a future Appearance Settings screen — UI not included.
struct ThemeSelectionOption: Hashable, Sendable, Identifiable {
    var id: ThemeIdentifier { metadata.identifier }
    var metadata: ThemeMetadata
    var isSelected: Bool
}

/// Settings-facing appearance state (model only).
struct AppearanceSettingsModel: Hashable, Sendable {
    var selectedTheme: ThemeIdentifier
    var options: [ThemeSelectionOption]

    static func make(
        selected: ThemeIdentifier,
        registry: ThemeRegistry = ThemeRegistry()
    ) -> AppearanceSettingsModel {
        let options = registry.allMetadata().map {
            ThemeSelectionOption(metadata: $0, isSelected: $0.identifier == selected)
        }
        return AppearanceSettingsModel(selectedTheme: selected, options: options)
    }
}
