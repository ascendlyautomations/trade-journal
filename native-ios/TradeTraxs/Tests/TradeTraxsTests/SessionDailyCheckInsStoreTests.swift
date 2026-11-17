import XCTest
@testable import TradeTraxs

@MainActor
final class SessionDailyCheckInsStoreTests: XCTestCase {
    private let profile = ProfileID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")

    override func tearDown() {
        SessionDailyCheckInsStore.shared.invalidate()
        super.tearDown()
    }

    func testNeedsLoadFalseForHydratedEmptyWindow() {
        let window = ("2026-01-01", "2026-03-31")
        SessionDailyCheckInsStore.shared.seed([], for: profile, range: window)

        XCTAssertFalse(
            SessionDailyCheckInsStore.shared.needsLoad(
                for: profile,
                startDate: window.0,
                endDate: window.1
            )
        )
        XCTAssertTrue(
            SessionDailyCheckInsStore.shared.hasSatisfiedWindow(
                for: profile,
                startDate: window.0,
                endDate: window.1
            )
        )
    }

    func testNeedsLoadTrueWhenWindowWiderThanSeededRange() {
        SessionDailyCheckInsStore.shared.seed([], for: profile, range: ("2026-02-01", "2026-02-28"))

        XCTAssertTrue(
            SessionDailyCheckInsStore.shared.needsLoad(
                for: profile,
                startDate: "2026-01-01",
                endDate: "2026-03-31"
            )
        )
    }

    func testNeedsLoadTrueForProfileMismatch() {
        let other = ProfileID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        SessionDailyCheckInsStore.shared.seed([], for: profile, range: ("2026-01-01", "2026-03-31"))

        XCTAssertTrue(
            SessionDailyCheckInsStore.shared.needsLoad(
                for: other,
                startDate: "2026-01-01",
                endDate: "2026-03-31"
            )
        )
    }
}