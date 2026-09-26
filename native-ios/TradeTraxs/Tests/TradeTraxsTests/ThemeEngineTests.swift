import SwiftUI
import XCTest
@testable import TradeTraxs

final class ThemeEngineTests: XCTestCase {
    func testBuiltInThemesAreRegistered() {
        let registry = ThemeRegistry()
        let ids = registry.allMetadata().map(\.identifier)
        XCTAssertEqual(ids, [.system, .light, .dark])
    }

    func testPersistenceRoundTrip() {
        let defaults = UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
        let persistence = UserDefaultsThemePersistence(defaults: defaults)
        persistence.saveSelectedTheme(.dark)
        XCTAssertEqual(persistence.loadSelectedTheme(), .dark)
    }

    func testThemeManagerRestoresPersistedSelection() {
        let defaults = UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
        let persistence = UserDefaultsThemePersistence(defaults: defaults)
        persistence.saveSelectedTheme(.dark)

        let manager = ThemeManager(persistence: persistence)
        XCTAssertEqual(manager.selectedIdentifier, .dark)
        XCTAssertEqual(manager.preferredColorScheme, .dark)
    }

    func testLegacyTradeTraxsPersistedValueMigratesToSystem() {
        let defaults = UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
        let persistence = UserDefaultsThemePersistence(defaults: defaults)
        defaults.set(ThemeIdentifier.legacyTradeTraxsPersistedValue, forKey: "theme.selectedIdentifier")

        let manager = ThemeManager(persistence: persistence)
        XCTAssertEqual(manager.selectedIdentifier, .system)
        XCTAssertEqual(persistence.loadSelectedTheme(), .system)
    }

    func testSystemThemeFollowsInterfaceStyle() {
        let manager = ThemeManager(
            persistence: UserDefaultsThemePersistence(
                defaults: UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
            )
        )
        manager.select(.system)
        XCTAssertNil(manager.preferredColorScheme)

        manager.updateInterfaceStyle(.light)
        let lightAccent = manager.colors.accent
        manager.updateInterfaceStyle(.dark)
        XCTAssertEqual(manager.selectedIdentifier, .system)
        _ = lightAccent
    }

    func testAppearanceSettingsModelPrepared() {
        let manager = ThemeManager(
            persistence: UserDefaultsThemePersistence(
                defaults: UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
            )
        )
        manager.select(.light)
        let model = manager.appearanceSettings
        XCTAssertEqual(model.selectedTheme, .light)
        XCTAssertEqual(model.options.count, 3)
        XCTAssertTrue(model.options.contains(where: \.isSelected))
    }

    func testUserFacingAppearanceExposesSystemLightDark() {
        let registry = ThemeRegistry()
        let model = AppearanceSettingsModel.makeUserFacing(
            selected: .dark,
            registry: registry
        )
        XCTAssertEqual(model.options.map(\.id), [.system, .light, .dark])
        XCTAssertEqual(model.selectedTheme, .dark)
        XCTAssertTrue(model.options.first { $0.id == .dark }?.isSelected == true)

        let legacy = AppearanceSettingsModel.makeUserFacing(
            selected: ThemeIdentifier(rawValue: ThemeIdentifier.legacyTradeTraxsPersistedValue),
            registry: registry
        )
        XCTAssertEqual(legacy.selectedTheme, .system)
        XCTAssertTrue(legacy.options.first { $0.id == .system }?.isSelected == true)
    }

    func testAppearanceControllerAllowsSystemLightDark() {
        let defaults = UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
        let manager = ThemeManager(
            persistence: UserDefaultsThemePersistence(defaults: defaults)
        )
        manager.select(.system)
        let controller = AppearanceSettingsController(themeManager: manager)
        controller.selectTheme(.dark, reduceMotion: true)
        XCTAssertEqual(manager.selectedIdentifier, .dark)
        controller.selectTheme(.light, reduceMotion: true)
        XCTAssertEqual(manager.selectedIdentifier, .light)
    }

    func testRegisterFutureThemeWithoutEngineChanges() {
        struct MidnightTheme: AppThemeProtocol {
            var metadata: ThemeMetadata {
                ThemeMetadata(
                    identifier: ThemeIdentifier(rawValue: "midnight"),
                    displayName: "Midnight",
                    detail: "Future theme",
                    isPremiumSignature: false,
                    supportsSystemAppearanceFollow: false
                )
            }

            var colorSchemeOverride: ColorScheme? { .dark }

            func palette(for colorScheme: ColorScheme) -> SemanticColorPalette {
                _ = colorScheme
                return ThemePalettes.darkFixed
            }
        }

        let registry = ThemeRegistry()
        registry.register(MidnightTheme())
        XCTAssertNotNil(registry.theme(for: ThemeIdentifier(rawValue: "midnight")))
        XCTAssertTrue(registry.allMetadata().contains { $0.identifier.rawValue == "midnight" })
    }

    func testSemanticAliasesExist() {
        let palette = ThemePalettes.darkFixed
        XCTAssertNotNil(palette.primaryBackground)
        XCTAssertNotNil(palette.positivePnL)
        XCTAssertNotNil(palette.skeleton)
        XCTAssertNotNil(palette.focus)
    }

    func testBootstrapIncludesThemeManager() {
        let environment = CompositionRoot.bootstrapAppEnvironment()
        XCTAssertNotNil(environment.themeManager)
        XCTAssertFalse(environment.themeManager.registry.allMetadata().isEmpty)
    }
}
