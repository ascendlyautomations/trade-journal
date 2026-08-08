import Foundation

/// Future Settings → Appearance screen contract.
///
/// UI is intentionally not built in this phase. ViewModels will call
/// ``ThemeManager/select(_:reduceMotion:)`` using ``AppearanceSettingsModel``.
protocol AppearanceSettingsPreparing: AnyObject {
    func makeAppearanceModel() -> AppearanceSettingsModel
    func selectTheme(_ identifier: ThemeIdentifier)
}

/// Production bridge from Settings (future) → Theme Engine.
final class AppearanceSettingsController: AppearanceSettingsPreparing {
    private let themeManager: ThemeManager

    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
    }

    func makeAppearanceModel() -> AppearanceSettingsModel {
        themeManager.appearanceSettings
    }

    func selectTheme(_ identifier: ThemeIdentifier) {
        themeManager.select(identifier)
    }
}
