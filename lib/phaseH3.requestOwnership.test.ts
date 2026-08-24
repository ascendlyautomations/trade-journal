import { describe, it, beforeEach } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))
import {
  buildReelsByTradeIdsCacheKey,
  clearReelsByTradeIdsInflight,
  getReelsByTradeIdsInflight,
  isReelsByTradeIdsCacheFresh,
  readReelsByTradeIdsCache,
  resetReelsByTradeIdsCacheForTests,
  setReelsByTradeIdsInflight,
  writeReelsByTradeIdsCache,
} from "./reelsByTradeIdsCache.ts"
import type { ReelRow } from "./reels.ts"
import { resolveStripeServerConfig } from "./stripeServerConfig.ts"

const ROOT = path.join(__dirname, "..")

function reelRowStub(id: string, tradeId: string): ReelRow {
  const now = new Date().toISOString()
  return {
    id,
    trade_id: tradeId,
    user_id: "viewer-a",
    caption: null,
    video_url: "https://example.com/reel.mp4",
    thumbnail_url: "",
    duration_seconds: null,
    visibility: "public",
    kind: null,
    created_at: now,
    updated_at: now,
  }
}

describe("Phase H3 — reels by trade IDs cache", () => {
  beforeEach(() => {
    resetReelsByTradeIdsCacheForTests()
  })

  it("canonicalizes duplicate and differently ordered trade IDs", () => {
    const a = buildReelsByTradeIdsCacheKey("viewer-a", ["b", "a", "a"])
    const b = buildReelsByTradeIdsCacheKey("viewer-a", ["a", "b"])
    assert.equal(a, b)
    assert.equal(a, "viewer-a:a,b")
  })

  it("caches successful empty results distinctly from missing entries", () => {
    const key = buildReelsByTradeIdsCacheKey("viewer-a", ["t1", "t2"])
    assert.ok(key)
    assert.equal(readReelsByTradeIdsCache(key), null)

    writeReelsByTradeIdsCache(key, new Map())
    const hit = readReelsByTradeIdsCache(key)
    assert.ok(hit)
    assert.equal(hit.map.size, 0)
    assert.equal(isReelsByTradeIdsCacheFresh(hit), true)
  })

  it("isolates viewer caches", () => {
    const keyA = buildReelsByTradeIdsCacheKey("viewer-a", ["t1"])!
    const keyB = buildReelsByTradeIdsCacheKey("viewer-b", ["t1"])!
    writeReelsByTradeIdsCache(keyA, new Map([["t1", reelRowStub("r1", "t1")]]))
    writeReelsByTradeIdsCache(keyB, new Map())

    assert.equal(readReelsByTradeIdsCache(keyA)?.map.size, 1)
    assert.equal(readReelsByTradeIdsCache(keyB)?.map.size, 0)
  })

  it("shares one in-flight promise per cache key", async () => {
    const key = buildReelsByTradeIdsCacheKey("viewer-a", ["t1"])!
    let calls = 0
    const promise = (async () => {
      calls += 1
      await new Promise((r) => setTimeout(r, 10))
      return new Map()
    })()
    setReelsByTradeIdsInflight(key, promise)
    const [a, b] = await Promise.all([
      getReelsByTradeIdsInflight(key),
      getReelsByTradeIdsInflight(key),
    ])
    await promise
    clearReelsByTradeIdsInflight(key)
    assert.equal(calls, 1)
    assert.equal(a, b)
  })

  it("wires fetchReelsByTradeIds to persistent viewer-scoped cache", () => {
    const src = fs.readFileSync(path.join(__dirname, "reels.ts"), "utf8")
    assert.match(src, /readReelsByTradeIdsCache\(cacheKey\)/)
    assert.match(src, /isReelsByTradeIdsCacheFresh\(cached\)/)
    assert.match(src, /writeReelsByTradeIdsCache\(cacheKey, map\)/)
    assert.match(src, /invalidateReelsByTradeIdsCache/)
    assert.doesNotMatch(
      src.slice(src.indexOf("export async function fetchReelsByTradeIds"), src.indexOf("async function loadReelsByTradeIdsOnce")),
      /if \(!.*\.length\)/
    )
  })

  it("clears reels cache on logout", () => {
    const src = fs.readFileSync(path.join(__dirname, "sessionUserCache.ts"), "utf8")
    assert.match(src, /invalidateReelsByTradeIdsCache/)
  })

  it("fresh revisit within TTL performs zero cache misses for empty result", () => {
    const tradeIds = [
      "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      "cccccccc-cccc-cccc-cccc-cccccccccccc",
      "dddddddd-dddd-dddd-dddd-dddddddddddd",
      "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
      "ffffffff-ffff-ffff-ffff-ffffffffffff",
      "11111111-1111-1111-1111-111111111111",
      "22222222-2222-2222-2222-222222222222",
      "33333333-3333-3333-3333-333333333333",
      "44444444-4444-4444-4444-444444444444",
    ]
    const viewer = "viewer-closeout-test"
    const cacheKey = buildReelsByTradeIdsCacheKey(viewer, tradeIds)
    assert.ok(cacheKey)

    let networkCalls = 0
    const simulateFetch = (
      ids: readonly string[],
      expectedKey: string = cacheKey
    ) => {
      const hitKey = buildReelsByTradeIdsCacheKey(viewer, ids)
      assert.equal(hitKey, expectedKey)
      assert.ok(hitKey)
      const cached = readReelsByTradeIdsCache(hitKey)
      if (cached && isReelsByTradeIdsCacheFresh(cached)) {
        return cached.map
      }
      networkCalls += 1
      writeReelsByTradeIdsCache(hitKey, new Map())
      return new Map()
    }

    simulateFetch(tradeIds)
    assert.equal(networkCalls, 1)
    simulateFetch([...tradeIds].reverse())
    assert.equal(networkCalls, 1)

    const subsetKey = buildReelsByTradeIdsCacheKey(viewer, tradeIds.slice(0, 5))
    assert.ok(subsetKey)
    assert.notEqual(subsetKey, cacheKey)
    simulateFetch(tradeIds.slice(0, 5), subsetKey)
    assert.equal(networkCalls, 2)
  })

  it("does not treat failed requests as cached empty results", () => {
    const viewer = "viewer-error-test"
    const ids = ["99999999-9999-9999-9999-999999999999"]
    const key = buildReelsByTradeIdsCacheKey(viewer, ids)
    assert.ok(key)
    assert.equal(readReelsByTradeIdsCache(key), null)

    const src = fs.readFileSync(path.join(__dirname, "reels.ts"), "utf8")
    const errorPath = src.slice(
      src.indexOf('console.error("[fetchReelsByTradeIds] query:"'),
      src.indexOf("const rows = (data ?? [])")
    )
    assert.match(errorPath, /throw error/)
    assert.equal(readReelsByTradeIdsCache(key), null)
  })
})

describe("Phase H3 — affiliate connect sync", () => {
  it("classifies Stripe auth failures as non-retryable billing unavailable", () => {
    const src = fs.readFileSync(
      path.join(ROOT, "app/api/affiliates/connect/sync/route.ts"),
      "utf8"
    )
    assert.match(src, /StripeAuthenticationError/)
    assert.match(src, /StripePermissionError/)
    assert.match(src, /category: "stripe_auth_invalid"/)
    assert.match(src, /retryable: false/)
    assert.match(src, /USER_FACING_ERROR_MESSAGES\.BILLING_UNAVAILABLE/)
  })

  it("returns dev-specific message when Stripe is not configured locally", () => {
    const src = fs.readFileSync(
      path.join(ROOT, "app/api/affiliates/connect/sync/route.ts"),
      "utf8"
    )
    assert.match(src, /stripe_not_configured/)
    assert.match(src, /STRIPE_SECRET_KEY in the server environment/)
    assert.match(src, /skipped: true/)
  })

  it("does not retry deterministic failures in the client", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "affiliateConnectSyncClient.ts"),
      "utf8"
    )
    assert.match(src, /DETERMINISTIC_FAILURE_CATEGORIES/)
    assert.match(src, /failureByViewer/)
    assert.match(src, /if \(failed && !failed\.retryable\)/)
    assert.match(src, /const retryable = body\.retryable === true/)
    assert.doesNotMatch(src, /status === 503/)
  })

  it("dedupes simultaneous sync callers through single-flight", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "affiliateConnectSyncClient.ts"),
      "utf8"
    )
    assert.match(src, /inflightByViewer/)
    assert.match(src, /if \(existing\) return existing\.promise/)
  })

  it("logs safe structured fields without secrets", () => {
    const src = fs.readFileSync(path.join(__dirname, "affiliateConnectSyncLog.ts"), "utf8")
    assert.match(src, /requestId/)
    assert.match(src, /stripeMode/)
    assert.match(src, /category/)
    assert.doesNotMatch(src, /STRIPE_SECRET_KEY/)
    assert.doesNotMatch(src, /service_role/)
  })

  it("maps transient Stripe failures to retryable 503", () => {
    const src = fs.readFileSync(
      path.join(ROOT, "app/api/affiliates/connect/sync/route.ts"),
      "utf8"
    )
    assert.match(src, /StripeConnectionError/)
    assert.match(src, /category: "stripe_transient"/)
    assert.match(src, /retryable: true/)
  })
})

describe("Phase H3 — stripe server config", () => {
  it("detects missing configuration without exposing secrets", () => {
    const prev = process.env.STRIPE_SECRET_KEY
    delete process.env.STRIPE_SECRET_KEY
    try {
      assert.deepEqual(resolveStripeServerConfig(), { status: "missing" })
    } finally {
      if (prev) process.env.STRIPE_SECRET_KEY = prev
    }
  })

  it("detects test and live key formats without returning values", () => {
    const prev = process.env.STRIPE_SECRET_KEY
    process.env.STRIPE_SECRET_KEY = "sk_test_example"
    assert.deepEqual(resolveStripeServerConfig(), {
      status: "configured",
      mode: "test",
    })
    process.env.STRIPE_SECRET_KEY = "sk_live_example"
    assert.deepEqual(resolveStripeServerConfig(), {
      status: "configured",
      mode: "live",
    })
    process.env.STRIPE_SECRET_KEY = "not-a-stripe-key"
    assert.deepEqual(resolveStripeServerConfig(), { status: "invalid_format" })
    if (prev) process.env.STRIPE_SECRET_KEY = prev
    else delete process.env.STRIPE_SECRET_KEY
  })
})
export {}
