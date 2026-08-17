import Foundation

/// Settings → Appearance bridge onto ``ThemeManager``.
protocol AppearanceSettingsPreparing: AnyObject {
    func makeAppearanceModel() -> AppearanceSettingsModel
    func selectTheme(_ identifier: ThemeIdentifier, reduceMotion: Bool)
}

/// Production bridge from Settings → Theme Engine.
final class AppearanceSettingsController: AppearanceSettingsPreparing {
    private let themeManager: ThemeManager

    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
    }

    func makeAppearanceModel() -> AppearanceSettingsModel {
        AppearanceSettingsModel.makeUserFacing(
            selected: themeManager.selectedIdentifier,
            registry: themeManager.registry
        )
    }

    func selectTheme(_ identifier: ThemeIdentifier, reduceMotion: Bool) {
        // Launch picker only exposes System + TradeTraxs.
        let allowed: Set<ThemeIdentifier> = [.system, .tradeTraxs]
        guard allowed.contains(identifier) else { return }
        themeManager.select(identifier, reduceMotion: reduceMotion)
    }
}
