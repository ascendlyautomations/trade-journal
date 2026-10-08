import XCTest
@testable import TradeTraxs

final class FeedScrollAwareHeaderTests: XCTestCase {
    func testHeaderVisibleAtTop() {
        var tracker = FeedScrollAwareHeaderTracker()
        XCTAssertFalse(tracker.apply(normalizedOffsetY: 0))
        XCTAssertFalse(tracker.isChromeHidden)
    }

    func testScrollDownHidesAfterThreshold() {
        var tracker = FeedScrollAwareHeaderTracker()
        _ = tracker.apply(normalizedOffsetY: 0)
        XCTAssertFalse(tracker.apply(normalizedOffsetY: 4))
        XCTAssertTrue(tracker.apply(normalizedOffsetY: 20))
        XCTAssertTrue(tracker.isChromeHidden)
    }

    func testScrollUpRevealsBeforeTop() {
        var tracker = FeedScrollAwareHeaderTracker()
        _ = tracker.apply(normalizedOffsetY: 0)
        _ = tracker.apply(normalizedOffsetY: 40)
        XCTAssertTrue(tracker.isChromeHidden)
        XCTAssertTrue(tracker.apply(normalizedOffsetY: 24))
        XCTAssertFalse(tracker.isChromeHidden)
    }

    func testReturnToTopForcesVisible() {
        var tracker = FeedScrollAwareHeaderTracker()
        _ = tracker.apply(normalizedOffsetY: 0)
        _ = tracker.apply(normalizedOffsetY: 50)
        XCTAssertTrue(tracker.isChromeHidden)
        XCTAssertTrue(tracker.apply(normalizedOffsetY: 2))
        XCTAssertFalse(tracker.isChromeHidden)
    }

    /// Mirrors scroll callbacks: tracker must be written back every sample, not only on visibility flips.
    func testRepeatedScrollCallbacksPersistTrackerAccumulation() {
        var stored = FeedScrollAwareHeaderTracker()
        _ = stored.apply(normalizedOffsetY: 0)

        func runSamples(persistEverySample: Bool) -> Bool {
            var state = stored
            for offset in stride(from: CGFloat(10), through: 1_200, by: 10) {
                var next = state
                _ = next.apply(normalizedOffsetY: offset)
                if persistEverySample {
                    state = next
                }
            }
            return state.isChromeHidden
        }

        XCTAssertFalse(runSamples(persistEverySample: false))
        XCTAssertTrue(runSamples(persistEverySample: true))
    }

    /// Navigation bar hide/show changes top inset without moving content (device: 47 → 91 pt).
    func testDashboardNavigationBarInsetJumpDoesNotToggleChrome() {
        var tracker = FeedScrollAwareHeaderTracker()
        _ = tracker.apply(
            normalizedOffsetY: 0,
            rawOffsetY: -47,
            contentInsetTop: 47,
            mode: .dashboardNavigationBar
        )
        XCTAssertFalse(tracker.isChromeHidden)

        XCTAssertFalse(
            tracker.apply(
                normalizedOffsetY: 44,
                rawOffsetY: -47,
                contentInsetTop: 91,
                mode: .dashboardNavigationBar
            )
        )
        XCTAssertFalse(tracker.isChromeHidden)

        XCTAssertFalse(
            tracker.apply(
                normalizedOffsetY: 0,
                rawOffsetY: -47,
                contentInsetTop: 47,
                mode: .dashboardNavigationBar
            )
        )
        XCTAssertFalse(tracker.isChromeHidden)
    }

    func testDashboardNavigationBarStableCoordinatesStillHideOnScroll() {
        var tracker = FeedScrollAwareHeaderTracker()
        _ = tracker.apply(
            normalizedOffsetY: 0,
            rawOffsetY: -47,
            contentInsetTop: 47,
            mode: .dashboardNavigationBar
        )
        XCTAssertFalse(tracker.apply(
            normalizedOffsetY: 4,
            rawOffsetY: -43,
            contentInsetTop: 47,
            mode: .dashboardNavigationBar
        ))
        XCTAssertTrue(tracker.apply(
            normalizedOffsetY: 20,
            rawOffsetY: -27,
            contentInsetTop: 47,
            mode: .dashboardNavigationBar
        ))
        XCTAssertTrue(tracker.isChromeHidden)
    }

    /// Feed feedback loop: toolbar hide (inset 0) then show (inset 47, compensated raw) must not reveal/hide again.
    func testNavigationBarHideShowCompensationDoesNotToggleChrome() {
        var tracker = FeedScrollAwareHeaderTracker()
        _ = tracker.apply(
            normalizedOffsetY: 0,
            rawOffsetY: -47,
            contentInsetTop: 47,
            mode: .navigationBarInsetStable
        )
        XCTAssertTrue(
            tracker.apply(
                normalizedOffsetY: 20,
                rawOffsetY: -27,
                contentInsetTop: 47,
                mode: .navigationBarInsetStable
            )
        )
        XCTAssertTrue(tracker.isChromeHidden)

        XCTAssertFalse(
            tracker.apply(
                normalizedOffsetY: 18.33,
                rawOffsetY: 18.33,
                contentInsetTop: 0,
                mode: .navigationBarInsetStable
            )
        )
        XCTAssertFalse(
            tracker.apply(
                normalizedOffsetY: 65.33,
                rawOffsetY: 18.33,
                contentInsetTop: 47,
                mode: .navigationBarInsetStable
            )
        )
        XCTAssertFalse(
            tracker.apply(
                normalizedOffsetY: 18.33,
                rawOffsetY: -28.67,
                contentInsetTop: 47,
                mode: .navigationBarInsetStable
            )
        )
        XCTAssertTrue(tracker.isChromeHidden)
    }

    /// Inset compensation must not clear scroll-up accumulation (Dashboard partial-header symptom).
    func testInsetCompensationPreservesScrollUpAccumulation() {
        var tracker = FeedScrollAwareHeaderTracker()
        _ = tracker.apply(
            normalizedOffsetY: 0,
            rawOffsetY: -47,
            contentInsetTop: 47,
            mode: .navigationBarInsetStable
        )
        XCTAssertTrue(
            tracker.apply(
                normalizedOffsetY: 24,
                rawOffsetY: -23,
                contentInsetTop: 47,
                mode: .navigationBarInsetStable
            )
        )
        XCTAssertTrue(tracker.isChromeHidden)

        _ = tracker.apply(
            normalizedOffsetY: 20,
            rawOffsetY: 20,
            contentInsetTop: 0,
            mode: .navigationBarInsetStable
        )
        XCTAssertFalse(
            tracker.apply(
                normalizedOffsetY: 65.33,
                rawOffsetY: 18.33,
                contentInsetTop: 47,
                mode: .navigationBarInsetStable
            )
        )
        XCTAssertTrue(
            tracker.apply(
                normalizedOffsetY: 58,
                rawOffsetY: 11,
                contentInsetTop: 47,
                mode: .navigationBarInsetStable
            )
        )
        XCTAssertFalse(tracker.isChromeHidden)
    }
}
