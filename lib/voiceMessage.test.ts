import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  formatVoiceDuration,
  isLikelySafariVoiceRecorder,
  isVoiceMessage,
  measurePcmPeak,
  voiceDurationSeconds,
} from "./voiceMessage.ts"

describe("formatVoiceDuration", () => {
  it("formats seconds as m:ss", () => {
    assert.equal(formatVoiceDuration(14), "0:14")
    assert.equal(formatVoiceDuration(74), "1:14")
    assert.equal(formatVoiceDuration(0), "0:00")
  })
})

describe("isVoiceMessage", () => {
  it("detects voice type and audio_url", () => {
    assert.equal(isVoiceMessage({ type: "voice" }), true)
    assert.equal(isVoiceMessage({ type: "VOICE" }), true)
    assert.equal(
      isVoiceMessage({ audio_url: "https://example.com/a.m4a" }),
      true
    )
    assert.equal(isVoiceMessage({ type: "text", content: "hi" }), false)
  })
})

describe("voiceDurationSeconds", () => {
  it("converts ms to seconds", () => {
    assert.equal(voiceDurationSeconds(14_000), 14)
    assert.equal(voiceDurationSeconds(null), undefined)
  })
})

describe("measurePcmPeak", () => {
  it("detects non-silent PCM", () => {
    assert.ok(measurePcmPeak([new Float32Array([0, 0.5, -0.25])]) > 0.1)
    assert.ok(measurePcmPeak([new Float32Array([0, 0, 0])]) < 0.002)
  })
})

describe("isLikelySafariVoiceRecorder", () => {
  it("is false without navigator", () => {
    assert.equal(isLikelySafariVoiceRecorder(), false)
  })
})
