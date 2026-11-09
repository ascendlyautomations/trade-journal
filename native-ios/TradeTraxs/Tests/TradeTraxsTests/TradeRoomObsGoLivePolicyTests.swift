import XCTest
@testable import TradeTraxs

final class TradeRoomObsGoLivePolicyTests: XCTestCase {
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
