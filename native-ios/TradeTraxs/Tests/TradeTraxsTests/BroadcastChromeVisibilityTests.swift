import LiveKit
import XCTest
@testable import TradeTraxs

final class BroadcastChromeVisibilityTests: XCTestCase {
    func testObsHostBarHiddenWhenManageSheetOpen() {
        XCTAssertFalse(
            BroadcastChromeVisibility.shouldShowObsHostBar(
                hasHostBarSession: true,
                isLivePublic: true,
                isManageSheetPresented: true
            )
        )
    }

    func testObsHostBarVisibleWhenLiveAndSheetDismissed() {
        XCTAssertTrue(
            BroadcastChromeVisibility.shouldShowObsHostBar(
                hasHostBarSession: true,
                isLivePublic: true,
                isManageSheetPresented: false
            )
        )
    }

    func testObsHostBarHiddenWhenNotLive() {
        XCTAssertFalse(
            BroadcastChromeVisibility.shouldShowObsHostBar(
                hasHostBarSession: true,
                isLivePublic: false,
                isManageSheetPresented: false
            )
        )
    }
}
