import XCTest
@testable import TradeTraxs

@MainActor
final class ProductAnalyticsCoordinatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ProductAnalyticsCoordinator.shared.bind(repository: nil)
        ProductAnalyticsCoordinator.shared.resetSession()
    }

    func testBindStartsSessionAfterLateRepositoryAttachment() async {
        let repo = SpyAnalyticsRepository()
        ProductAnalyticsCoordinator.shared.bind(repository: repo)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(
            repo.events.contains { $0.0 == ProductAnalyticsEventName.sessionStarted.rawValue },
            "Session should start when repository binds after lifecycle"
        )
        XCTAssertTrue(
            repo.events.contains { $0.0 == ProductAnalyticsEventName.appOpened.rawValue },
            "App open should be recorded when repository binds"
        )
    }

    func testBackgroundFlushesPendingEvents() async {
        let repo = SpyAnalyticsRepository()
        ProductAnalyticsCoordinator.shared.bind(repository: repo)
        ProductAnalyticsCoordinator.shared.noteScreen(.dashboard)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(repo.flushCount, 0)
        ProductAnalyticsCoordinator.shared.handleEnterBackground()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertGreaterThanOrEqual(repo.flushCount, 1)
    }
}

private final class SpyAnalyticsRepository: AnalyticsRepository, @unchecked Sendable {
    var events: [(String, [String: String])] = []
    var flushCount = 0

    func track(event: String, properties: [String: String]) async {
        events.append((event, properties))
    }

    func flushPendingEvents() async {
        flushCount += 1
    }
}