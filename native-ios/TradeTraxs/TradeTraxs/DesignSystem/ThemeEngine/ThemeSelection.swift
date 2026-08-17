import Foundation

/// Row model for Appearance Settings.
struct ThemeSelectionOption: Hashable, Sendable, Identifiable {
    var id: ThemeIdentifier { metadata.identifier }
    var metadata: ThemeMetadata
    var isSelected: Bool
}

/// Settings-facing appearance state (model only).
struct AppearanceSettingsModel: Hashable, Sendable {
    var selectedTheme: ThemeIdentifier
    var options: [ThemeSelectionOption]

    /// Full registry snapshot (includes Light / Dark for tests + future).
    static func make(
        selected: ThemeIdentifier,
        registry: ThemeRegistry = ThemeRegistry()
    ) -> AppearanceSettingsModel {
        let options = registry.allMetadata().map {
            ThemeSelectionOption(metadata: $0, isSelected: $0.identifier == selected)
        }
        return AppearanceSettingsModel(selectedTheme: selected, options: options)
    }

    /// Launch-facing picker — System + TradeTraxs only.
    ///
    /// Light / Dark remain registered for future exposure via ``ThemeRegistry``.
    static func makeUserFacing(
        selected: ThemeIdentifier,
        registry: ThemeRegistry = ThemeRegistry()
    ) -> AppearanceSettingsModel {
        let visible: [ThemeIdentifier] = [.system, .tradeTraxs]
        let displaySelected: ThemeIdentifier = selected == .tradeTraxs ? .tradeTraxs : .system
        let options = visible.compactMap { id -> ThemeSelectionOption? in
            guard let theme = registry.theme(for: id) else { return nil }
            return ThemeSelectionOption(
                metadata: theme.metadata,
                isSelected: theme.metadata.identifier == displaySelected
            )
        }
        return AppearanceSettingsModel(selectedTheme: displaySelected, options: options)
    }
}
