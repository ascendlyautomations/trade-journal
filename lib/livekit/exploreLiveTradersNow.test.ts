import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { isExploreDiscoverableLiveBroadcastRow } from "./exploreLiveTradersNow.ts"

const baseRow = {
  id: "sess-1",
  room_id: "room-1",
  broadcaster_user_id: "user-1",
  started_at: "2026-11-07T12:00:00.000Z",
  video_source: "camera",
  visibility: "public",
  primary_media_publisher_identity: null,
  rooms: {
    id: "room-1",
    name: "NQ Room",
    slug: "nq-room",
    is_private: false,
  },
}

describe("isExploreDiscoverableLiveBroadcastRow", () => {
  it("includes public broadcasts in non-private rooms", () => {
    assert.equal(isExploreDiscoverableLiveBroadcastRow(baseRow), true)
  })

  it("excludes private trade rooms", () => {
    assert.equal(
      isExploreDiscoverableLiveBroadcastRow({
        ...baseRow,
        rooms: { ...baseRow.rooms!, is_private: true },
      }),
      false
    )
  })

  it("excludes preparing OBS sessions", () => {
    assert.equal(
      isExploreDiscoverableLiveBroadcastRow({
        ...baseRow,
        visibility: "preparing",
        video_source: "obs",
      }),
      false
    )
  })

  it("excludes explicit preparing visibility", () => {
    assert.equal(
      isExploreDiscoverableLiveBroadcastRow({
        ...baseRow,
        visibility: "preparing",
      }),
      false
    )
  })
})
