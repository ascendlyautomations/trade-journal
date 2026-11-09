import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { normalizeVisibilityFromRow } from "./tradeRoomBroadcastSession.ts"

describe("normalizeVisibilityFromRow", () => {
  it("legacy browser row without visibility stays public", () => {
    assert.equal(
      normalizeVisibilityFromRow({
        video_source: "screen",
        broadcast_source: "browser",
      }),
      "public"
    )
  })

  it("new browser broadcast with explicit public stays public", () => {
    assert.equal(
      normalizeVisibilityFromRow({
        video_source: "camera",
        visibility: "public",
      }),
      "public"
    )
  })

  it("OBS with missing visibility defaults to preparing (never infer public)", () => {
    assert.equal(
      normalizeVisibilityFromRow({
        video_source: "obs",
      }),
      "preparing"
    )
  })

  it("OBS identified only by broadcast_source without visibility defaults to preparing", () => {
    assert.equal(
      normalizeVisibilityFromRow({
        video_source: "screen",
        broadcast_source: "obs",
      }),
      "preparing"
    )
  })

  it("OBS published session with explicit public in DB", () => {
    assert.equal(
      normalizeVisibilityFromRow({
        video_source: "obs",
        visibility: "public",
      }),
      "public"
    )
  })

  it("preparing stored explicitly for any video source", () => {
    assert.equal(
      normalizeVisibilityFromRow({
        visibility: "preparing",
        video_source: "screen",
      }),
      "preparing"
    )
  })
})
