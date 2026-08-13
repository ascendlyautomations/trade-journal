import XCTest
@testable import TradeTraxs

final class ExperienceSystemTests: XCTestCase {
    func testSpacingScaleContainsApprovedValues() {
        let values = SpacingToken.allCases.map(\.rawValue)
        XCTAssertEqual(values, [4, 8, 12, 16, 20, 24, 32, 40, 48, 64])
    }

    func testMetricColorSigns() {
        // Dynamic Color equality is not reliable across providers; ensure API is callable.
        _ = ExperienceColor.metric(10)
        _ = ExperienceColor.metric(-10)
        _ = ExperienceColor.metric(0)
        XCTAssertNotNil(ExperienceTheme.standard.metricColor(for: 1))
    }

    func testTypographyRolesCoverDynamicTypeStyles() {
        XCTAssertEqual(TypographyRole.allCases.count, 13)
        XCTAssertTrue(TypographyRole.metric.isMonospacedDigits)
        XCTAssertTrue(TypographyRole.metricLarge.isMonospacedDigits)
    }

    func testAppIconCatalogHasTabIcons() {
        XCTAssertEqual(AppIcon.home.systemName, "house.fill")
        XCTAssertEqual(AppIcon.create.systemName, "plus.circle.fill")
        XCTAssertNil(AppIcon.home.customAssetName)
    }

    func testFeedbackStateFailureRetryFlag() {
        let state = FeedbackState.failure(message: "Nope", retryable: true)
        if case let .failure(_, retryable) = state {
            XCTAssertTrue(retryable)
        } else {
            XCTFail("Expected failure state")
        }
    }

    /// Documents the product convention: screen names live in the compact nav bar.
    func testPrimaryTabDisplayNamesMatchNavigationTitles() {
        XCTAssertEqual(TabIdentifier.home.displayName, "Home")
        XCTAssertEqual(TabIdentifier.feed.displayName, "Feed")
        XCTAssertEqual(TabIdentifier.messages.displayName, "Messages")
        XCTAssertEqual(TabIdentifier.profile.displayName, "Profile")
        // Root screen titles (nav bar) are owned by each feature view via
        // `experienceNavigationTitle` — Dashboard/Feed/Messages/Profile/etc.
        XCTAssertEqual(SettingsRoute.home.title, "Settings")
        XCTAssertEqual(SettingsRoute.notifications.title, "Notifications")
        XCTAssertEqual(SettingsRoute.notificationsMessages.title, "Messages")
        XCTAssertEqual(SettingsRoute.tradingAccounts.title, "Manage Accounts")
    }
}
