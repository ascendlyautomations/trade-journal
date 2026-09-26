import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"
import {
  REALTIME_IN_FILTER_MAX_IDS,
  buildRealtimeInFilterChunks,
  stableIdKey,
} from "./realtimeFilters.ts"

function bindingCount(reelCount: number): number {
  const ids = Array.from({ length: reelCount }, (_, index) => `reel-${index}`)
  return buildRealtimeInFilterChunks("reel_id", ids).length
}

describe("profile reel-likes chunks", () => {
  it("uses one filtered binding through 100 reels and chunks after that", () => {
    assert.equal(bindingCount(1), 1)
    assert.equal(bindingCount(5), 1)
    assert.equal(bindingCount(20), 1)
    assert.equal(bindingCount(50), 1)
    assert.equal(bindingCount(100), 1)
    assert.equal(bindingCount(101), 2)
    assert.equal(bindingCount(200), 2)
    assert.equal(bindingCount(250), 3)
    assert.equal(REALTIME_IN_FILTER_MAX_IDS, 100)
  })

  it("does not subscribe when there are no reel ids", () => {
    assert.deepEqual(buildRealtimeInFilterChunks("reel_id", []), [])
  })

  it("dedupes and ignores order in the subscription key", () => {
    assert.equal(stableIdKey(["b", "a", "a"]), stableIdKey(["a", "b"]))
    assert.deepEqual(buildRealtimeInFilterChunks("reel_id", ["b", "a", "a"]), [
      "reel_id=in.(a,b)",
    ])
  })

  it("never emits an unfiltered reel_likes filter", () => {
    const filters = buildRealtimeInFilterChunks(
      "reel_id",
      Array.from({ length: 250 }, (_, index) => `reel-${index}`)
    )
    assert.equal(filters.length, 3)
    for (const filter of filters) {
      assert.match(filter, /^reel_id=in\.\(.+\)$/)
    }
  })
})

describe("profile page reel-likes subscription", () => {
  it("chunks loaded reels and does not bind one eq filter per reel", () => {
    const src = readFileSync(
      new URL("../app/profile/[id]/page.tsx", import.meta.url),
      "utf8"
    )
    assert.match(src, /buildRealtimeInFilterChunks\("reel_id", reelIds\)/)
    assert.match(src, /stableIdKey\(profileReels\.map/)
    assert.match(src, /filter: likeFilter/)
    assert.match(src, /reelIdFrom\(payload\.new\) \|\| reelIdFrom\(payload\.old\)/)
    assert.doesNotMatch(src, /reel_id=eq\.\$\{/)
    assert.match(src, /if \(likeFilters\.length === 0\) return/)
  })
})
