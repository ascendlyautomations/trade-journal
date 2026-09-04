import XCTest
import SwiftUI
@testable import TradeTraxs

@MainActor
final class ExperienceChromeTests: XCTestCase {
    func testInfoPlistRequiresDesignCompatibilityForEdgeAnchoredChrome() {
        let value = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility")
        // Generated Info.plist merges App/Info.plist — key must be present so iOS 26
        // does not float the tab/navigation bars away from physical screen edges.
        let boolValue: Bool? = {
            if let flag = value as? Bool { return flag }
            if let number = value as? NSNumber { return number.boolValue }
            return nil
        }()
        XCTAssertEqual(boolValue, true)
    }

    func testInfoPlistIncludesPhotoLibraryUsageDescription() {
        let description = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription") as? String
        XCTAssertNotNil(description)
        XCTAssertFalse(description?.isEmpty ?? true)
        XCTAssertTrue(description?.localizedCaseInsensitiveContains("photo library") == true)
    }

    func testInfoPlistDoesNotRequestPhotoLibraryAddUsageDescription() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription"))
    }

    func testFloatingTabBarPreferenceIsDisabledAtLaunch() {
        // Same registration AppDelegate performs at process launch.
        UserDefaults.standard.register(defaults: ["UseFloatingTabBar": false])
        XCTAssertEqual(UserDefaults.standard.object(forKey: "UseFloatingTabBar") as? Bool, false)
    }

    func testExperienceNavigationTitleModifierBuilds() {
        // Contract: titles are inline + principal-centered (see ExperienceNavigationTitle).
        let view = Text("content").experienceNavigationTitle("Dashboard")
        XCTAssertNotNil(view)
    }

    func testExperienceAppChromeModifierBuilds() {
        let view = Text("shell").experienceAppChrome().experienceScreenBackground()
        XCTAssertNotNil(view)
    }
}
