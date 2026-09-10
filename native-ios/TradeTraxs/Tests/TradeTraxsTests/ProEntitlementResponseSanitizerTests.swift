import XCTest
@testable import TradeTraxs

final class ProEntitlementResponseSanitizerTests: XCTestCase {
    func test403AlwaysReturnsNeutralCopy() {
        let message = ProEntitlementResponseSanitizer.message(
            statusCode: 403,
            error: "Pro required",
            reply: "Upgrade your plan on the web to unlock it."
        )
        XCTAssertEqual(message, TraxProFeatureMessaging.featureRequired)
    }

    func testUpgradeOnWebReplyIsSanitized() {
        XCTAssertTrue(
            ProEntitlementResponseSanitizer.containsPurchaseSteering(
                "This AI feature is available on TraxPro. Upgrade your plan on the web to unlock it."
            )
        )
        let sanitized = ProEntitlementResponseSanitizer.sanitizedOrNeutral(
            "Upgrade your plan on the web to unlock it."
        )
        XCTAssertEqual(sanitized, TraxProFeatureMessaging.featureRequired)
    }

    func testNeutralErrorsPassThrough() {
        let message = ProEntitlementResponseSanitizer.sanitizedOrNeutral("Slow down — try again in a moment.")
        XCTAssertEqual(message, "Slow down — try again in a moment.")
    }
}
