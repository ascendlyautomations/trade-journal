import XCTest
@testable import TradeTraxs

final class BroadcastObsProgramVideoTests: XCTestCase {
    func testDetectsObsFromBroadcastOrVideoSource() {
        XCTAssertTrue(
            BroadcastObsProgramVideo.isObsSession(broadcastSource: "obs", videoSource: "screen")
        )
        XCTAssertTrue(
            BroadcastObsProgramVideo.isObsSession(broadcastSource: "browser", videoSource: "obs")
        )
        XCTAssertFalse(
            BroadcastObsProgramVideo.isObsSession(broadcastSource: "browser", videoSource: "screen")
        )
    }

    func testResolvesProgramPublisherIdentityFallback() {
        let sid = "11111111-2222-3333-4444-555555555555"
        XCTAssertEqual(
            BroadcastObsProgramVideo.resolvedProgramPublisherIdentity(
                sessionId: sid,
                primaryFromToken: nil,
                primaryFromStatus: nil
            ),
            "tt-obs-\(sid)"
        )
        XCTAssertEqual(
            BroadcastObsProgramVideo.resolvedProgramPublisherIdentity(
                sessionId: sid,
                primaryFromToken: "tt-obs-custom",
                primaryFromStatus: nil
            ),
            "tt-obs-custom"
        )
    }
}
