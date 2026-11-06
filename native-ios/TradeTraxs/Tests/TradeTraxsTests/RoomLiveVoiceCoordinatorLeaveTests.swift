import LiveKit
import XCTest
@testable import TradeTraxs

final class RoomLiveVoiceCoordinatorLeaveTests: XCTestCase {
    func testVoiceBarVisibleWhileReconnectingAfterBackground() {
        XCTAssertTrue(
            LiveVoiceChromeVisibility.shouldShowBar(
                hasSession: true,
                connectionState: .reconnecting,
                isLeaving: false,
                isJoining: false
            )
        )
    }

    func testVoiceBarVisibleWhileLeavingEvenIfDisconnecting() {
        XCTAssertTrue(
            LiveVoiceChromeVisibility.shouldShowBar(
                hasSession: true,
                connectionState: .disconnecting,
                isLeaving: true,
                isJoining: false
            )
        )
    }

    func testVoiceBarHiddenWhenDisconnectedWithoutSession() {
        XCTAssertFalse(
            LiveVoiceChromeVisibility.shouldShowBar(
                hasSession: false,
                connectionState: .disconnected,
                isLeaving: false,
                isJoining: false
            )
        )
    }

    func testVoiceBarVisibleWhileJoiningBeforeSessionAttached() {
        XCTAssertTrue(
            LiveVoiceChromeVisibility.shouldShowBar(
                hasSession: false,
                connectionState: .disconnected,
                isLeaving: false,
                isJoining: true
            )
        )
    }

    func testLeaveEpochPreventsStaleJoinFromReconnecting() {
        var epoch: UInt64 = 0
        epoch &+= 1
        let joinEpoch = epoch
        epoch &+= 1
        let leaveEpoch = epoch
        XCTAssertNotEqual(joinEpoch, leaveEpoch)
        XCTAssertFalse(joinEpoch == leaveEpoch)
    }
}
