import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { resolveBroadcastLiveVisibility } from "./broadcastVisibilityMerge.ts"

describe("resolveBroadcastLiveVisibility", () => {
  it("keeps OBS private prep when lite poll omits visibility and publicLive", () => {
    const r = resolveBroadcastLiveVisibility({
      mergedLive: true,
      mergedBroadcastSessionId: "sess-1",
      mergedVideoSource: "obs",
      mergedVisibility: undefined,
      mergedPublicLive: undefined,
      prevLive: true,
      prevBroadcastSessionId: "sess-1",
      prevVisibility: "preparing",
      prevPublicLive: false,
    })
    assert.deepEqual(r, { visibility: "preparing", publicLive: false })
  })

  it("does not flip OBS to public when publicLive is omitted but was false", () => {
    const r = resolveBroadcastLiveVisibility({
      mergedLive: true,
      mergedBroadcastSessionId: "sess-1",
      mergedVideoSource: "obs",
      mergedVisibility: undefined,
      mergedPublicLive: undefined,
      prevLive: true,
      prevBroadcastSessionId: "sess-1",
      prevVisibility: undefined,
      prevPublicLive: false,
    })
    assert.deepEqual(r, { visibility: "preparing", publicLive: false })
  })

  it("uses explicit server preparing", () => {
    const r = resolveBroadcastLiveVisibility({
      mergedLive: true,
      mergedBroadcastSessionId: "sess-1",
      mergedVideoSource: "obs",
      mergedVisibility: "preparing",
      mergedPublicLive: undefined,
      prevLive: true,
      prevBroadcastSessionId: "sess-1",
      prevVisibility: "preparing",
      prevPublicLive: false,
    })
    assert.deepEqual(r, { visibility: "preparing", publicLive: false })
  })
})
