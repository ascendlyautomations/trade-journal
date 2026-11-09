import XCTest
@testable import TradeTraxs

final class TradeRoomObsGoLivePolicyTests: XCTestCase {
    func testObsBroadcasterOwnershipMatch() {
        let roomID = RoomID(rawValue: "11111111-1111-1111-1111-111111111111")
        let userId = "user-host"
        let liveObs = RoomBroadcastStatus(
            isLive: true,
            broadcastSessionId: "sess",
            broadcasterUserId: userId,
            broadcasterDisplayName: nil,
            voiceMode: "broadcast_only",
            videoSource: "obs",
            broadcastSource: "obs",
            primaryMediaPublisherIdentity: nil,
            hostConnected: true,
            primaryMediaPublisherConnected: true,
            viewerCount: 4
        )
        XCTAssertTrue(
            RoomBroadcastCoordinator.matchesCurrentUserObsBroadcast(
                status: liveObs,
                statusRoomID: roomID,
                roomID: roomID,
                userId: userId
            )
        )
        XCTAssertFalse(
            RoomBroadcastCoordinator.matchesCurrentUserObsBroadcast(
                status: liveObs,
                statusRoomID: roomID,
                roomID: roomID,
                userId: "other-user"
            )
        )
        XCTAssertFalse(
            RoomBroadcastCoordinator.matchesCurrentUserObsBroadcast(
                status: liveObs,
                statusRoomID: roomID,
                roomID: roomID,
                userId: nil
            )
        )
        var browser = liveObs
        browser.videoSource = "camera"
        browser.broadcastSource = "browser"
        XCTAssertFalse(
            RoomBroadcastCoordinator.matchesCurrentUserObsBroadcast(
                status: browser,
                statusRoomID: roomID,
                roomID: roomID,
                userId: userId
            )
        )
    }

    func testEnabledOnlyWhenPreparingAndEncoderConnectedAndNotBusy() {
        XCTAssertFalse(
            TradeRoomObsGoLivePolicy.canGoLiveToRoom(
                isPreparingObs: false,
                isBusy: false,
                encoderConnected: true
            )
        )
        XCTAssertFalse(
            TradeRoomObsGoLivePolicy.canGoLiveToRoom(
                isPreparingObs: true,
                isBusy: true,
                encoderConnected: true
            )
        )
        XCTAssertFalse(
            TradeRoomObsGoLivePolicy.canGoLiveToRoom(
                isPreparingObs: true,
                isBusy: false,
                encoderConnected: false
            )
        )
        XCTAssertTrue(
            TradeRoomObsGoLivePolicy.canGoLiveToRoom(
                isPreparingObs: true,
                isBusy: false,
                encoderConnected: true
            )
        )
    }
}
