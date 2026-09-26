import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  REALTIME_IN_FILTER_MAX_IDS,
  buildRealtimeInFilter,
  buildRealtimeInFilterChunks,
  resolveRealtimeInFilter,
} from "./realtimeFilters.ts"

describe("resolveRealtimeInFilter", () => {
  it("distinguishes empty, ready, and too many ids", () => {
    assert.deepEqual(resolveRealtimeInFilter("user_id", []), { status: "empty" })
    assert.equal(
      resolveRealtimeInFilter("user_id", ["b", "a"]).status,
      "ready"
    )
    const tooMany = resolveRealtimeInFilter(
      "user_id",
      Array.from({ length: REALTIME_IN_FILTER_MAX_IDS + 1 }, (_, index) =>
        String(index)
      )
    )
    assert.equal(tooMany.status, "too_many")
    if (tooMany.status === "too_many") {
      assert.equal(tooMany.idCount, REALTIME_IN_FILTER_MAX_IDS + 1)
    }
  })

  it("does not treat an oversized list as a usable single filter", () => {
    const ids = Array.from({ length: 101 }, (_, index) => `user-${index}`)
    assert.equal(buildRealtimeInFilter("user_id", ids), null)
    assert.equal(resolveRealtimeInFilter("user_id", ids).status, "too_many")
  })
})

describe("buildRealtimeInFilterChunks", () => {
  it("returns no filters when there are no ids", () => {
    assert.deepEqual(buildRealtimeInFilterChunks("reel_id", []), [])
  })

  it("keeps a list within the cap as one filtered binding", () => {
    const filters = buildRealtimeInFilterChunks("reel_id", ["b", "a", "a"])
    assert.deepEqual(filters, ["reel_id=in.(a,b)"])
  })

  it("chunks 250 ids into filtered groups and never emits an unfiltered value", () => {
    const ids = Array.from({ length: 250 }, (_, index) =>
      `user-${String(index).padStart(3, "0")}`
    )
    const filters = buildRealtimeInFilterChunks("user_id", ids)
    assert.equal(filters.length, 3)
    for (const filter of filters) {
      assert.match(filter, /^user_id=in\.\(.+\)$/)
      const inner = filter.slice("user_id=in.(".length, -1)
      assert.ok(inner.split(",").length <= REALTIME_IN_FILTER_MAX_IDS)
    }
    const covered = filters.flatMap((filter) =>
      filter.slice("user_id=in.(".length, -1).split(",")
    )
    assert.equal(covered.length, 250)
  })
})
