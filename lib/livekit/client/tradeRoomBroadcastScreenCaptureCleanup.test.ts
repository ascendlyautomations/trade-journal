import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { stopLiveMediaStreamTracks } from "./tradeRoomBroadcastScreenOverlaySession.ts"

describe("stopLiveMediaStreamTracks", () => {
  it("stops only live tracks and returns count", () => {
    let liveStops = 0
    let endedStops = 0
    const live = {
      readyState: "live",
      stop: () => {
        liveStops += 1
      },
    } as unknown as MediaStreamTrack
    const ended = {
      readyState: "ended",
      stop: () => {
        endedStops += 1
      },
    } as unknown as MediaStreamTrack

    assert.equal(stopLiveMediaStreamTracks([live, ended]), 1)
    assert.equal(liveStops, 1)
    assert.equal(endedStops, 0)
  })

  it("is safe to call twice on the same track reference", () => {
    const state = { readyState: "live", stops: 0 }
    const live = {
      get readyState() {
        return state.readyState
      },
      stop: () => {
        state.stops += 1
        state.readyState = "ended"
      },
    } as unknown as MediaStreamTrack

    assert.equal(stopLiveMediaStreamTracks([live]), 1)
    assert.equal(stopLiveMediaStreamTracks([live]), 0)
    assert.equal(state.stops, 1)
  })
})
