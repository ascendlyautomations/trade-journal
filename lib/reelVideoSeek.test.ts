import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  buildReelThumbnailSeekCandidates,
  firstVisibleReelSeekTime,
} from "./reelVideoSeek.ts"

describe("firstVisibleReelSeekTime", () => {
  it("uses min(0.1, duration/10) and never returns 0", () => {
    assert.equal(firstVisibleReelSeekTime(90), 0.1)
    assert.equal(firstVisibleReelSeekTime(0.5), 0.05)
    assert.equal(firstVisibleReelSeekTime(1), 0.1)
    assert.ok(firstVisibleReelSeekTime(0.2) > 0)
  })

  it("falls back safely for invalid durations", () => {
    assert.equal(firstVisibleReelSeekTime(NaN), 0.05)
    assert.equal(firstVisibleReelSeekTime(-1), 0.05)
    assert.equal(firstVisibleReelSeekTime(0), 0.05)
  })
})

describe("buildReelThumbnailSeekCandidates", () => {
  it("never includes exact t=0 and retries later frames", () => {
    const candidates = buildReelThumbnailSeekCandidates(90)
    assert.equal(candidates[0], 0.1)
    assert.ok(candidates.every((t) => t > 0))
    assert.ok(candidates.includes(0.25))
    assert.ok(candidates.includes(0.5))
    assert.ok(candidates.includes(1))
  })
})
