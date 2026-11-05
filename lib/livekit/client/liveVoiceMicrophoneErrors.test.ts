import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  isLiveVoiceMicrophoneAccessError,
  liveVoiceMicrophoneErrorMessage,
} from "./liveVoiceMicrophoneErrors.ts"

describe("liveVoiceMicrophoneErrors", () => {
  it("detects standard getUserMedia DOMException names", () => {
    assert.equal(
      isLiveVoiceMicrophoneAccessError(
        new DOMException("Requested device not found", "NotFoundError")
      ),
      true
    )
    assert.equal(
      isLiveVoiceMicrophoneAccessError(
        new DOMException("Permission denied", "NotAllowedError")
      ),
      true
    )
    assert.equal(
      isLiveVoiceMicrophoneAccessError(
        new DOMException("Could not start video source", "NotReadableError")
      ),
      true
    )
    assert.equal(isLiveVoiceMicrophoneAccessError(new Error("network")), false)
  })

  it("maps microphone errors to user-facing copy", () => {
    assert.match(
      liveVoiceMicrophoneErrorMessage(
        new DOMException("Requested device not found", "NotFoundError")
      ),
      /No microphone/
    )
    assert.match(
      liveVoiceMicrophoneErrorMessage(
        new DOMException("Permission denied", "NotAllowedError")
      ),
      /blocked/
    )
  })
})
