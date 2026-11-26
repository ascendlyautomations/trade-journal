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

    func testStoryLikeUsesDedicatedInteractionKind() {
        XCTAssertEqual(InteractionTarget.story(StoryID("s1")).kind, .story)
        XCTAssertEqual(ContentLikeTable.from(.story).rawValue, "story_likes")
    }
}
