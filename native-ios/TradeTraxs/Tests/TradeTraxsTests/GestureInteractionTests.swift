import XCTest
@testable import TradeTraxs

@MainActor
final class GestureInteractionTests: XCTestCase {
    func testSwipeToDismissThresholdDefaultsAreModest() {
        let modifier = SwipeToDismissModifier(onDismiss: {})
        XCTAssertEqual(modifier.distanceThreshold, 110)
        XCTAssertEqual(modifier.velocityThreshold, 900)
        XCTAssertTrue(modifier.isEnabled)
    }

    func testDoubleTapLikeModifierDefaultsEnabled() {
        let modifier = DoubleTapLikeModifier(onDoubleTap: {})
        XCTAssertTrue(modifier.isEnabled)
        XCTAssertNil(modifier.onSingleTap)
    }

    func testStoriesDoNotExposeLikeTargets() {
        // Stories have no InteractionContentKind — double-tap Like must not be invented.
        let kinds: [InteractionContentKind] = [
            .trade, .profilePost, .reel, .feedPost, .achievement,
        ]
        XCTAssertFalse(kinds.map(\.rawValue).contains("story"))
        XCTAssertEqual(kinds.count, 5)
    }
}
