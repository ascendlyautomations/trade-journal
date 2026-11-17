import XCTest
@testable import TradeTraxs

final class BroadcastPlaybackLevelTests: XCTestCase {
    func testMutePreservesGainAndUnmuteRestoresIt() {
        let gain = 0.4
        XCTAssertEqual(BroadcastPlaybackLevel.trackVolume(muted: true, gain: gain), 0)
        XCTAssertEqual(BroadcastPlaybackLevel.trackVolume(muted: false, gain: gain), 0.4)
    }

    func testLateAudioSubscriptionInheritsPlayback() {
        XCTAssertTrue(BroadcastPlaybackLevel.shouldApplyPlayback(on: .audio))
        XCTAssertTrue(BroadcastPlaybackLevel.shouldApplyPlayback(on: .video))
        XCTAssertFalse(BroadcastPlaybackLevel.shouldApplyPlayback(on: .other))
        XCTAssertEqual(BroadcastPlaybackLevel.trackVolume(muted: true, gain: 0.25), 0)
    }

    func testGainStaysInsideZeroToOne() {
        XCTAssertEqual(BroadcastPlaybackLevel.clampedGain(1.4), 1)
        XCTAssertEqual(BroadcastPlaybackLevel.clampedGain(-0.2), 0)
    }
}
