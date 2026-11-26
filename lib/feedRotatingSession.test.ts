import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  beginFeedRotatingSession,
  feedContentKey,
  isFeedRankCursor,
  setFeedScanCursor,
  getFeedRotatingSession,
} from "./feedRotatingSession.ts"
import { __resetBackendV2FlagsForTests } from "./backendV2/flags.ts"

describe("feedRotatingSession", () => {
  it("builds composite content keys", () => {
    assert.equal(feedContentKey("trade", "abc"), "post|abc")
    assert.equal(feedContentKey("profile", "x"), "profile_post|x")
  })

  it("classifies rank vs chrono cursors", () => {
    assert.equal(isFeedRankCursor("42.5|post|00000000-0000-0000-0000-000000000001"), true)
    assert.equal(
      isFeedRankCursor("2026-01-01T00:00:00.000Z|post|00000000-0000-0000-0000-000000000001"),
      false
    )
  })

  it("stores scan cursor on the frozen session", () => {
    beginFeedRotatingSession("u1", "following", "all")
    setFeedScanCursor(
      "u1",
      "following",
      "all",
      "2026-01-01T00:00:00.000Z|post|00000000-0000-0000-0000-000000000001"
    )
    assert.equal(
      getFeedRotatingSession("u1", "following", "all")?.scanCursor,
      "2026-01-01T00:00:00.000Z|post|00000000-0000-0000-0000-000000000001"
    )
  })
})

describe("feedRotatingRank flag default", () => {
  it("defaults OFF", async () => {
    __resetBackendV2FlagsForTests()
    const { isBackendV2Enabled } = await import("./backendV2/flags.ts")
    assert.equal(isBackendV2Enabled("feedRotatingRank"), false)
  })
})