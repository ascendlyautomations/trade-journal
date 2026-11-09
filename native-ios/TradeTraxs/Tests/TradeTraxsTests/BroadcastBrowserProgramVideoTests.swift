import LiveKit
import XCTest
@testable import TradeTraxs

final class BroadcastBrowserProgramVideoTests: XCTestCase {
    func testPrefersScreenOverCameraWhenBothPublished() {
        let snaps = [
            BroadcastBrowserProgramVideo.PublicationChoice(
                source: .camera,
                publicationSid: "cam-1"
            ),
            BroadcastBrowserProgramVideo.PublicationChoice(
                source: .screenShareVideo,
                publicationSid: "screen-1"
            ),
        ]
        let picked = BroadcastBrowserProgramVideo.pickProgramVideoPublicationSnapshots(snaps)
        XCTAssertEqual(picked?.source, .screenShareVideo)
        XCTAssertEqual(picked?.publicationSid, "screen-1")
    }

    func testReturnsCameraWhenScreenUnpublished() {
        let snaps = [
            BroadcastBrowserProgramVideo.PublicationChoice(
                source: .camera,
                publicationSid: "cam-2"
            ),
        ]
        let picked = BroadcastBrowserProgramVideo.pickProgramVideoPublicationSnapshots(snaps)
        XCTAssertEqual(picked?.source, .camera)
    }
}
