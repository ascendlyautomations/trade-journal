import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { Track } from "livekit-client"
import { findLocalBroadcastVideoPublication } from "./tradeRoomBroadcastLocalPreview.ts"

describe("tradeRoomBroadcastLocalPreview", () => {
  it("prefers camera publication for camera streams", () => {
    const room = {
      localParticipant: {
        videoTrackPublications: new Map([
          [
            "cam",
            {
              source: Track.Source.Camera,
              track: { sid: "cam" },
              videoTrack: { sid: "cam" },
            },
          ],
        ]),
      },
    } as never

    const pub = findLocalBroadcastVideoPublication(room, "camera")
    assert.equal(pub?.source, Track.Source.Camera)
  })

  it("prefers screen-share publication for screen streams", () => {
    const room = {
      localParticipant: {
        videoTrackPublications: new Map([
          [
            "screen",
            {
              source: Track.Source.ScreenShare,
              track: { sid: "screen" },
              videoTrack: { sid: "screen" },
            },
          ],
        ]),
      },
    } as never

    const pub = findLocalBroadcastVideoPublication(room, "screen")
    assert.equal(pub?.source, Track.Source.ScreenShare)
  })
})
