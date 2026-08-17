import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class SettingsAppearanceViewModel {
    private let controller: AppearanceSettingsPreparing
    private(set) var model: AppearanceSettingsModel

    init(themeManager: ThemeManager) {
        let controller = AppearanceSettingsController(themeManager: themeManager)
        self.controller = controller
        self.model = controller.makeAppearanceModel()
        normalizeLegacySelectionIfNeeded(themeManager: themeManager)
    }

    init(controller: AppearanceSettingsPreparing) {
        self.controller = controller
        self.model = controller.makeAppearanceModel()
    }

    func refresh() {
        model = controller.makeAppearanceModel()
    }

    func select(_ identifier: ThemeIdentifier, reduceMotion: Bool) {
        guard model.options.contains(where: { $0.id == identifier }) else { return }
        guard model.selectedTheme != identifier else { return }
        ExperienceHaptics.play(.selection)
        controller.selectTheme(identifier, reduceMotion: reduceMotion)
        model = controller.makeAppearanceModel()
    }

    /// Light / Dark remain in the registry but are not user-facing — map to System.
    private func normalizeLegacySelectionIfNeeded(themeManager: ThemeManager) {
        let current = themeManager.selectedIdentifier
        guard current != .system, current != .tradeTraxs else { return }
        themeManager.select(.system, reduceMotion: true)
        model = controller.makeAppearanceModel()
    }
}
