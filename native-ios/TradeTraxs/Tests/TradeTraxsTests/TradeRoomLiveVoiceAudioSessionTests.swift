import LiveKit
import XCTest
@testable import TradeTraxs

final class TradeRoomLiveVoiceAudioSessionTests: XCTestCase {
    func testSessionRequirementMapping() {
        XCTAssertEqual(
            TradeRoomLiveVoiceSessionRequirement.forLiveVoice(requiresRecording: true),
            .playbackAndRecording
        )
        XCTAssertEqual(
            TradeRoomLiveVoiceSessionRequirement.forLiveVoice(requiresRecording: false),
            .playbackOnly
        )
    }
}
