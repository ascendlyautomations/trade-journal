import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  isBroadcastCameraPublication,
  isBroadcastScreenSharePublication,
} from "./tradeRoomBroadcastVideo.ts"
import { Track } from "livekit-client"

describe("tradeRoomBroadcastVideo — track source classification", () => {
  it("identifies screen-share vs camera publications", () => {
    assert.equal(
      isBroadcastScreenSharePublication({
        source: Track.Source.ScreenShare,
      } as never),
      true
    )
    assert.equal(
      isBroadcastCameraPublication({
        source: Track.Source.Camera,
      } as never),
      true
    )
    assert.equal(
      isBroadcastScreenSharePublication({
        source: Track.Source.Camera,
      } as never),
      false
    )
  })
})
