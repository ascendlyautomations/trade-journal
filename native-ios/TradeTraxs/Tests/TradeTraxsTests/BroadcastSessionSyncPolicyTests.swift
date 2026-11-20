import XCTest

@testable import TradeTraxs

final class BroadcastSessionSyncPolicyTests: XCTestCase {
    func testFallbackIntervals() {
        XCTAssertEqual(
            BroadcastSessionSyncPolicy.fallbackInteractiveInterval(healthy: true),
            BroadcastSessionSyncPolicy.fallbackInteractiveHealthySeconds
        )
        XCTAssertEqual(
            BroadcastSessionSyncPolicy.fallbackInteractiveInterval(healthy: false),
            BroadcastSessionSyncPolicy.fallbackInteractiveUnhealthySeconds
        )
        XCTAssertEqual(
            BroadcastSessionSyncPolicy.fallbackStatusInterval(healthy: true),
            BroadcastSessionSyncPolicy.fallbackStatusWatchingHealthySeconds
        )
    }

    func testRealtimeHealthyWhenRecentSignal() {
        let now = Date()
        XCTAssertTrue(
            BroadcastSessionSyncPolicy.isRealtimeHealthy(lastSignalAt: now.addingTimeInterval(-10), now: now)
        )
        XCTAssertFalse(
            BroadcastSessionSyncPolicy.isRealtimeHealthy(lastSignalAt: now.addingTimeInterval(-120), now: now)
        )
        XCTAssertFalse(BroadcastSessionSyncPolicy.isRealtimeHealthy(lastSignalAt: nil, now: now))
    }

    func testEndedAtParsing() {
        let json = #"{"ended_at":"2026-11-18T12:00:00Z","id":"abc"}"#.data(using: .utf8)!
        XCTAssertEqual(BroadcastRealtimeSessionRow.endedAt(from: json), "2026-11-18T12:00:00Z")
    }
}