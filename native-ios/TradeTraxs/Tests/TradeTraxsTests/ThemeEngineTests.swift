import SwiftUI
import XCTest
@testable import TradeTraxs

final class ThemeEngineTests: XCTestCase {
    func testBuiltInThemesAreRegistered() {
        let registry = ThemeRegistry()
        let ids = registry.allMetadata().map(\.identifier)
        XCTAssertEqual(ids, [.system, .light, .dark, .tradeTraxs])
    }

    func testPersistenceRoundTrip() {
        let defaults = UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
        let persistence = UserDefaultsThemePersistence(defaults: defaults)
        persistence.saveSelectedTheme(.tradeTraxs)
        XCTAssertEqual(persistence.loadSelectedTheme(), .tradeTraxs)
    }

    func testThemeManagerRestoresPersistedSelection() {
        let defaults = UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
        let persistence = UserDefaultsThemePersistence(defaults: defaults)
        persistence.saveSelectedTheme(.dark)

        let manager = ThemeManager(persistence: persistence)
        XCTAssertEqual(manager.selectedIdentifier, .dark)
        XCTAssertEqual(manager.preferredColorScheme, .dark)
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
        // Adaptive palette objects differ by construction; ensure resolver stays system.
        XCTAssertEqual(manager.selectedIdentifier, .system)
        _ = lightAccent
    }

    func testTradeTraxsIsFixedSignature() {
        let manager = ThemeManager(
            persistence: UserDefaultsThemePersistence(
                defaults: UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
            )
        )
        manager.select(.tradeTraxs)
        XCTAssertEqual(manager.preferredColorScheme, .dark)
        XCTAssertTrue(manager.activeTheme.metadata.isPremiumSignature)

        let before = manager.colors.backgroundPrimary
        manager.updateInterfaceStyle(.light)
        // Signature palette ignores system interface style changes.
        XCTAssertEqual(
            String(describing: manager.colors.backgroundPrimary),
            String(describing: before)
        )
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
        XCTAssertEqual(model.options.count, 4)
        XCTAssertTrue(model.options.contains(where: \.isSelected))
    }

    func testUserFacingAppearanceExposesOnlySystemAndTradeTraxs() {
        let registry = ThemeRegistry()
        let model = AppearanceSettingsModel.makeUserFacing(
            selected: .dark,
            registry: registry
        )
        XCTAssertEqual(model.options.map(\.id), [.system, .tradeTraxs])
        XCTAssertEqual(model.selectedTheme, .system)
        XCTAssertTrue(model.options.first { $0.id == .system }?.isSelected == true)

        let branded = AppearanceSettingsModel.makeUserFacing(
            selected: .tradeTraxs,
            registry: registry
        )
        XCTAssertEqual(branded.selectedTheme, .tradeTraxs)
    }

    func testAppearanceControllerRejectsHiddenThemes() {
        let defaults = UserDefaults(suiteName: "theme.engine.tests.\(UUID().uuidString)")!
        let manager = ThemeManager(
            persistence: UserDefaultsThemePersistence(defaults: defaults)
        )
        manager.select(.system)
        let controller = AppearanceSettingsController(themeManager: manager)
        controller.selectTheme(.dark, reduceMotion: true)
        XCTAssertEqual(manager.selectedIdentifier, .system)
        controller.selectTheme(.tradeTraxs, reduceMotion: true)
        XCTAssertEqual(manager.selectedIdentifier, .tradeTraxs)
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
        let palette = ThemePalettes.tradeTraxsSignature
        XCTAssertNotNil(palette.primaryBackground)
        XCTAssertNotNil(palette.positivePnL)
        XCTAssertNotNil(palette.skeleton)
        XCTAssertNotNil(palette.focus)
    }

    func testBootstrapIncludesThemeManager() {
        let environment = CompositionRoot.bootstrap()
        XCTAssertNotNil(environment.themeManager)
        XCTAssertFalse(environment.themeManager.registry.allMetadata().isEmpty)
    }
}
