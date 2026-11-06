import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { getLiveVoiceRemoteAudioDiagnostics } from "./tradeRoomLiveVoiceRemoteAudio.ts"

describe("tradeRoomLiveVoiceRemoteAudio diagnostics", () => {
  it("reports disconnected defaults when room is null", () => {
    const d = getLiveVoiceRemoteAudioDiagnostics(null, false)
    assert.equal(d.connectionState, "disconnected")
    assert.equal(d.canPlaybackAudio, false)
    assert.equal(d.remoteAudioTrackCount, 0)
    assert.equal(d.attachedRemoteElementCount, 0)
  })
})
