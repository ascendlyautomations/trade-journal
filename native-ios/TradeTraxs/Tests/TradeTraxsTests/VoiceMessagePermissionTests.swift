import AVFoundation
import XCTest
@testable import TradeTraxs

final class VoiceMessagePermissionTests: XCTestCase {
    func testDeniedMicrophoneCanBeRequestedAgain() {
        XCTAssertTrue(VoiceMessageRecorder.canStart(from: .idle))
        XCTAssertFalse(VoiceMessageRecorder.canStart(from: .recording))
    }

    @MainActor
    func testBackgroundLeavesAnIdleRecorderIdle() {
        let recorder = VoiceMessageRecorder()
        recorder.handleEnteredBackground()
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertNil(recorder.completedRecording)
    }

    func testSettingsPromptOnlyAfterMicrophoneWasDenied() {
        XCTAssertTrue(VoiceMessageRecorder.needsSettingsPrompt(permission: .denied))
        XCTAssertFalse(VoiceMessageRecorder.needsSettingsPrompt(permission: .undetermined))
        XCTAssertFalse(VoiceMessageRecorder.needsSettingsPrompt(permission: .granted))
    }
}
