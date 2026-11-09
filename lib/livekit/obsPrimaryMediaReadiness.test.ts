import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { TrackType } from "@livekit/protocol"
import { primaryPublisherHasPublishableVideo } from "./obsPrimaryMediaReadiness.ts"

describe("primaryPublisherHasPublishableVideo", () => {
  it("false when participant is missing", () => {
    assert.equal(primaryPublisherHasPublishableVideo(undefined), false)
    assert.equal(primaryPublisherHasPublishableVideo(null), false)
  })

  it("false when no tracks", () => {
    assert.equal(primaryPublisherHasPublishableVideo({ tracks: [] } as never), false)
  })

  it("false when only audio", () => {
    assert.equal(
      primaryPublisherHasPublishableVideo({
        tracks: [{ type: TrackType.AUDIO, muted: false }],
      } as never),
      false
    )
  })

  it("false when video track is muted", () => {
    assert.equal(
      primaryPublisherHasPublishableVideo({
        tracks: [{ type: TrackType.VIDEO, muted: true }],
      } as never),
      false
    )
  })

  it("true when unmuted video track is published", () => {
    assert.equal(
      primaryPublisherHasPublishableVideo({
        tracks: [{ type: TrackType.VIDEO, muted: false }],
      } as never),
      true
    )
  })
})
