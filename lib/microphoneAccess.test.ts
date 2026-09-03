import { describe, it } from "node:test"
import assert from "node:assert/strict"
import { describeMicrophoneAccessFailure } from "./microphoneAccess.ts"

describe("describeMicrophoneAccessFailure", () => {
  it("maps NotAllowedError to blocked settings copy", () => {
    const result = describeMicrophoneAccessFailure({
      name: "NotAllowedError",
      message: "Permission denied",
    })
    assert.equal(result.phase, "denied")
    assert.match(result.message, /browser settings/i)
  })

  it("maps NotFoundError to no microphone copy", () => {
    const result = describeMicrophoneAccessFailure({
      name: "NotFoundError",
      message: "Requested device not found",
    })
    assert.equal(result.phase, "unsupported")
    assert.match(result.message, /No microphone/i)
  })

  it("maps NotReadableError to device in use copy", () => {
    const result = describeMicrophoneAccessFailure({
      name: "NotReadableError",
      message: "Could not start audio source",
    })
    assert.equal(result.phase, "unsupported")
    assert.match(result.message, /already in use/i)
  })
})
