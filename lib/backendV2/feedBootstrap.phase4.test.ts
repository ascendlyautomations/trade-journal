import { describe, it, beforeEach } from "node:test"
import { feedBootstrapFixture, } from "./fixtures.ts"
import { compareFeedBootstraps, } from "./feedBootstrapCompare.ts"
import { feedBootstrapCacheKey, readFeedBootstrapCache, writeFeedBootstrapCache, clearFeedBootstrapCache, } from "./feedBootstrapCache.ts"
import { beginFeedBootstrapFlight, __resetFeedBootstrapFlightsForTests, } from "./feedBootstrapSingleFlight.ts"
import { decodeFeedBootstrapV1, } from "./contracts.ts"
import { isBackendV2Enabled, resolveBackendV2Flag, __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, } from "./flags.ts"
import assert from "node:assert/strict"

describe("Backend V2 feed bootstrap (Phase 4)", () => {
  beforeEach(() => {
    clearFeedBootstrapCache()
    __resetFeedBootstrapFlightsForTests()
    __resetBackendV2FlagsForTests()
  })

  it("decodes fixture with stories + page_meta", () => {
    const decoded = decodeFeedBootstrapV1(
      JSON.parse(JSON.stringify(feedBootstrapFixture))
    )
    assert.equal(decoded.data.content_filter, "all")
    assert.ok(Array.isArray(decoded.data.stories))
    assert.equal(decoded.data.page_meta.returned, 1)
  })

  it("feed flag defaults ON and can be rolled back", () => {
    assert.equal(isBackendV2Enabled("feed"), true)
    assert.equal(resolveBackendV2Flag("feed").source, "default")
    __setBackendV2FlagForTests("feed", false)
    assert.equal(isBackendV2Enabled("feed"), false)
    assert.equal(resolveBackendV2Flag("feed").source, "test")
  })

  it("compare detects item id mismatch", () => {
    const rest = JSON.parse(JSON.stringify(feedBootstrapFixture))
    const rpc = JSON.parse(JSON.stringify(feedBootstrapFixture))
    rpc.data.items = []
    const mismatches = compareFeedBootstraps(rest, rpc)
    assert.ok(mismatches.some((m) => m.path === "items.ids"))
  })

  it("cache is keyed by scope/filter/cursor", () => {
    const uid = feedBootstrapFixture.meta.viewer_id
    assert.ok(uid)
    const keyA = feedBootstrapCacheKey({
      userId: uid,
      scope: "following",
      contentFilter: "all",
      cursor: null,
    })
    const keyB = feedBootstrapCacheKey({
      userId: uid,
      scope: "global",
      contentFilter: "all",
      cursor: null,
    })
    writeFeedBootstrapCache(keyA, uid, feedBootstrapFixture, "rpc")
    assert.ok(readFeedBootstrapCache(keyA))
    assert.equal(readFeedBootstrapCache(keyB), null)
  })

  it("single-flight shares one start", async () => {
    let starts = 0
    const start = async () => {
      starts += 1
      await new Promise((r) => setTimeout(r, 15))
      return { ok: true, starts }
    }
    const [a, b] = await Promise.all([
      beginFeedBootstrapFlight("k1", "u1", start),
      beginFeedBootstrapFlight("k1", "u1", start),
    ])
    assert.equal(starts, 1)
    assert.equal(a.starts, 1)
    assert.equal(b.starts, 1)
  })

  it("env can enable feed flag", () => {
    __setBackendV2FlagForTests("feed", true)
    assert.equal(isBackendV2Enabled("feed"), true)
  })

  it("NEXT_PUBLIC_BACKEND_V2_FEED=0 rolls feed back and leaves unrelated flags off", () => {
    const prev = process.env.NEXT_PUBLIC_BACKEND_V2_FEED
    process.env.NEXT_PUBLIC_BACKEND_V2_FEED = "0"
    try {
      assert.equal(isBackendV2Enabled("feed"), false)
      assert.equal(resolveBackendV2Flag("feed").source, "env")
      assert.equal(isBackendV2Enabled("messages"), true)
      for (const key of [
        "session",
        "dashboard",
        "profile",
        "rooms",
        "propFirm",
      ] as const) {
        assert.equal(isBackendV2Enabled(key), false, key)
      }
    } finally {
      if (prev === undefined) delete process.env.NEXT_PUBLIC_BACKEND_V2_FEED
      else process.env.NEXT_PUBLIC_BACKEND_V2_FEED = prev
    }
  })

  it("clearing one user leaves another user's feed cache", () => {
    const a = feedBootstrapCacheKey({
      userId: "user-a",
      scope: "global",
      contentFilter: "all",
      cursor: null,
    })
    const b = feedBootstrapCacheKey({
      userId: "user-b",
      scope: "following",
      contentFilter: "reels",
      cursor: "cursor-1",
    })
    writeFeedBootstrapCache(a, "user-a", feedBootstrapFixture, "rpc")
    writeFeedBootstrapCache(b, "user-b", feedBootstrapFixture, "rpc")
    clearFeedBootstrapCache("user-a")
    assert.equal(readFeedBootstrapCache(a), null)
    assert.ok(readFeedBootstrapCache(b))
  })
})
export {}
