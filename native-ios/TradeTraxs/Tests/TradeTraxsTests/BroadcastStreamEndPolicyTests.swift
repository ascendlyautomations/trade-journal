import LiveKit
import XCTest
@testable import TradeTraxs

final class BroadcastStreamEndPolicyTests: XCTestCase {
    private let roomA = RoomID("room-a")
    private let roomB = RoomID("room-b")

    func testRemoteStreamEndingRequiresTwoSuccessfulNotLivePolls() {
        XCTAssertFalse(
            BroadcastStreamEndPolicy.shouldEndWatchFromStatusPoll(
                isWatching: true,
                watchRoomID: roomA,
                polledRoomID: roomA,
                responseLive: false,
                pollSucceeded: true,
                consecutiveSuccessfulNotLivePolls: 1
            )
        )
        XCTAssertTrue(
            BroadcastStreamEndPolicy.shouldEndWatchFromStatusPoll(
                isWatching: true,
                watchRoomID: roomA,
                polledRoomID: roomA,
                responseLive: false,
                pollSucceeded: true,
                consecutiveSuccessfulNotLivePolls: 2
            )
        )
    }

    func testVoluntaryLeaveSuppressesPopup() {
        XCTAssertFalse(
            BroadcastStreamEndPolicy.shouldPresentStreamEndedPopup(
                isVoluntaryLeave: true,
                alreadyPresentedForSessionId: nil,
                sessionId: "sess-1"
            )
        )
    }

    func testTemporaryNetworkLossDoesNotIncrementNotLiveOnFailedPoll() {
        let previous = 1
        XCTAssertEqual(
            BroadcastStreamEndPolicy.nextConsecutiveNotLivePollCount(
                pollSucceeded: false,
                responseLive: false,
                previousCount: previous
            ),
            previous
        )
        XCTAssertFalse(
            BroadcastStreamEndPolicy.shouldEndWatchFromStatusPoll(
                isWatching: true,
                watchRoomID: roomA,
                polledRoomID: roomA,
                responseLive: false,
                pollSucceeded: false,
                consecutiveSuccessfulNotLivePolls: previous
            )
        )
    }

    func testReconnectingDefersStreamEnd() {
        XCTAssertTrue(
            BroadcastStreamEndPolicy.shouldDeferStreamEndForConnectionState(.reconnecting)
        )
        XCTAssertTrue(
            BroadcastStreamEndPolicy.shouldDeferStreamEndForConnectionState(.connecting)
        )
    }

    func testDuplicateEndNotificationsShowPopupOncePerSession() {
        XCTAssertTrue(
            BroadcastStreamEndPolicy.shouldPresentStreamEndedPopup(
                isVoluntaryLeave: false,
                alreadyPresentedForSessionId: nil,
                sessionId: "sess-1"
            )
        )
        XCTAssertFalse(
            BroadcastStreamEndPolicy.shouldPresentStreamEndedPopup(
                isVoluntaryLeave: false,
                alreadyPresentedForSessionId: "sess-1",
                sessionId: "sess-1"
            )
        )
    }

    func testStalePollForDifferentRoomDoesNotEndWatch() {
        XCTAssertFalse(
            BroadcastStreamEndPolicy.shouldEndWatchFromStatusPoll(
                isWatching: true,
                watchRoomID: roomA,
                polledRoomID: roomB,
                responseLive: false,
                pollSucceeded: true,
                consecutiveSuccessfulNotLivePolls: 5
            )
        )
    }

    func testBroadcasterDisconnectEndsWatch() {
        XCTAssertTrue(
            BroadcastStreamEndPolicy.shouldEndWatchFromBroadcasterDisconnect(
                isWatching: true,
                isVoluntaryLeave: false,
                disconnectedIdentity: "broadcaster-1",
                broadcasterIdentity: "broadcaster-1",
                broadcastSourceIsObs: false
            )
        )
        XCTAssertFalse(
            BroadcastStreamEndPolicy.shouldEndWatchFromBroadcasterDisconnect(
                isWatching: true,
                isVoluntaryLeave: true,
                disconnectedIdentity: "broadcaster-1",
                broadcasterIdentity: "broadcaster-1",
                broadcastSourceIsObs: false
            )
        )
    }

    func testObsHostDisconnectDoesNotEndWatch() {
        XCTAssertFalse(
            BroadcastStreamEndPolicy.shouldEndWatchFromBroadcasterDisconnect(
                isWatching: true,
                isVoluntaryLeave: false,
                disconnectedIdentity: "host-uuid",
                broadcasterIdentity: "host-uuid",
                broadcastSourceIsObs: true
            )
        )
    }

    func testLiveReturnsToZeroResetsNotLiveStreak() {
        XCTAssertEqual(
            BroadcastStreamEndPolicy.nextConsecutiveNotLivePollCount(
                pollSucceeded: true,
                responseLive: true,
                previousCount: 3
            ),
            0
        )
    }
}
