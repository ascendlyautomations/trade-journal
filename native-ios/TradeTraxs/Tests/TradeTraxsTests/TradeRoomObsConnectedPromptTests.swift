import XCTest
@testable import TradeTraxs

@MainActor
final class TradeRoomObsConnectedPromptTests: XCTestCase {
    func testGoLiveReadinessUsesEncoderNotPreview() {
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