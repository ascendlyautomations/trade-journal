import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { discoverableFromBroadcastStatusPayload } from "./tradeRoomBroadcastDiscoverable.ts"

describe("discoverableFromBroadcastStatusPayload", () => {
  it("is false when live and visibility omitted (lite/stale poll)", () => {
    assert.equal(
      discoverableFromBroadcastStatusPayload({
        live: true,
        visibility: undefined,
      }),
      false
    )
  })

  it("is false when live and preparing", () => {
    assert.equal(
      discoverableFromBroadcastStatusPayload({
        live: true,
        publicLive: false,
        visibility: "preparing",
      }),
      false
    )
  })

  it("is true when publicLive is true", () => {
    assert.equal(
      discoverableFromBroadcastStatusPayload({
        live: true,
        publicLive: true,
      }),
      true
    )
  })

  it("is true when visibility is public", () => {
    assert.equal(
      discoverableFromBroadcastStatusPayload({
        live: true,
        visibility: "public",
      }),
      true
    )
  })
})
