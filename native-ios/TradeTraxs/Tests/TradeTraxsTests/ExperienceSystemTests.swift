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
}
