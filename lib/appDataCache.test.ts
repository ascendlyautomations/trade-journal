import { describe, it, beforeEach } from "node:test"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { applyBrokerImportedTradeToCache, clearAppDataCache, getCachedTrades, isTradesHistoryComplete, mergeTradesInCache, prependTradeInCache, removeTradeFromCache, setTradesCache, upsertTradeInCache, } from "./appDataCache.ts"
import assert from "node:assert/strict"

describe("appDataCache", () => {
  const userId = "user-1"

  beforeEach(() => {
    clearAppDataCache()
  })

  it("stores and returns cached trades", () => {
    setTradesCache(userId, [{ id: "t1", pnl: 100 }])
    assert.deepEqual(getCachedTrades(userId), [{ id: "t1", pnl: 100 }])
  })

  it("upserts an existing trade", () => {
    setTradesCache(userId, [{ id: "t1", pnl: 100, ticker: "ES" }])
    upsertTradeInCache(userId, { id: "t1", pnl: 200 })
    assert.deepStrictEqual(getCachedTrades(userId)?.[0], {
      id: "t1",
      pnl: 200,
      ticker: "ES",
    })
  })

  it("prepends a new trade", () => {
    setTradesCache(userId, [{ id: "t1" }])
    prependTradeInCache(userId, { id: "t2" })
    assert.deepEqual(
      getCachedTrades(userId)?.map((t) => t.id),
      ["t2", "t1"]
    )
  })

  it("removes a trade by id", () => {
    setTradesCache(userId, [{ id: "t1" }, { id: "t2" }])
    removeTradeFromCache(userId, "t1")
    assert.deepEqual(
      getCachedTrades(userId)?.map((t) => t.id),
      ["t2"]
    )
  })

  it("merges imported trades without dropping existing rows", () => {
    setTradesCache(userId, [{ id: "t1", pnl: 1 }])
    mergeTradesInCache(userId, [
      { id: "t2", pnl: 2, created_at: "2026-01-02T00:00:00Z" },
      { id: "t1", pnl: 99, created_at: "2026-01-01T00:00:00Z" },
    ])
    const rows = getCachedTrades(userId) ?? []
    assert.equal(rows.length, 2)
    assert.equal(rows.find((r) => r.id === "t1")?.pnl, 99)
  })

  it("preserves incomplete history flag across upserts", () => {
    setTradesCache(userId, [{ id: "t1" }], { historyComplete: false })
    upsertTradeInCache(userId, { id: "t1", pnl: 5 })
    // Incomplete caches must stay available (not blocked by a loading flag).
    assert.equal(getCachedTrades(userId)?.[0]?.pnl, 5)
    assert.equal(isTradesHistoryComplete(userId), false)
  })

  it("patches a broker trade into a complete cache without clearing completeness", () => {
    setTradesCache(
      userId,
      [{ id: "t1", pnl: 10, created_at: "2026-01-01T00:00:00Z", import_source: "tradovate" }],
      { historyComplete: true }
    )
    const result = applyBrokerImportedTradeToCache(
      userId,
      "INSERT",
      {
        id: "t2",
        pnl: 25,
        created_at: "2026-02-01T00:00:00Z",
        import_source: "tradovate",
        ticker: "NQ",
      }
    )
    assert.equal(result.needsWindowLoad, false)
    assert.equal(isTradesHistoryComplete(userId), true)
    assert.deepEqual(
      getCachedTrades(userId)?.map((trade) => trade.id),
      ["t2", "t1"]
    )
  })

  it("keeps a recent-window cache incomplete when a broker trade is patched in", () => {
    setTradesCache(
      userId,
      [{ id: "t1", pnl: 1, created_at: "2026-01-02T00:00:00Z" }],
      { historyComplete: false }
    )
    applyBrokerImportedTradeToCache(userId, "UPDATE", {
      id: "t1",
      pnl: 9,
      created_at: "2026-01-02T00:00:00Z",
      import_source: "rithmic",
    })
    assert.equal(isTradesHistoryComplete(userId), false)
    assert.equal(getCachedTrades(userId)?.[0]?.pnl, 9)
  })

  it("replaces a broker trade by id and keeps fields the event did not send", () => {
    setTradesCache(
      userId,
      [{ id: "t1", pnl: 1, ticker: "ES", created_at: "2026-01-01T00:00:00Z", import_source: "tradovate" }],
      { historyComplete: true }
    )
    applyBrokerImportedTradeToCache(userId, "UPDATE", {
      id: "t1",
      pnl: 40,
      import_source: "tradovate",
    })
    const row = getCachedTrades(userId)?.[0]
    assert.equal(row?.pnl, 40)
    assert.equal(row?.ticker, "ES")
    assert.equal(getCachedTrades(userId)?.length, 1)
  })

  it("removes a broker trade on delete and ignores a non-broker row", () => {
    setTradesCache(
      userId,
      [
        { id: "broker", pnl: 1, import_source: "tradovate", created_at: "2026-01-02T00:00:00Z" },
        { id: "manual", pnl: 2, import_source: "manual", created_at: "2026-01-01T00:00:00Z" },
      ],
      { historyComplete: true }
    )
    applyBrokerImportedTradeToCache(userId, "DELETE", null, { id: "broker" })
    applyBrokerImportedTradeToCache(userId, "INSERT", {
      id: "manual-2",
      pnl: 3,
      import_source: "csv",
    })
    assert.deepEqual(
      getCachedTrades(userId)?.map((trade) => trade.id),
      ["manual"]
    )
    assert.equal(isTradesHistoryComplete(userId), true)
  })

  it("does not seed a one-row complete cache when the session has no trades yet", () => {
    const result = applyBrokerImportedTradeToCache(userId, "INSERT", {
      id: "t-new",
      pnl: 5,
      import_source: "tradovate",
      created_at: "2026-03-01T00:00:00Z",
    })
    assert.equal(result.needsWindowLoad, true)
    assert.equal(getCachedTrades(userId), null)
    assert.equal(isTradesHistoryComplete(userId), false)
  })

  it("broker realtime does not force a full-journal reload", () => {
    const hookPath = path.join(
      path.dirname(fileURLToPath(import.meta.url)),
      "useBrokerImportedTradesRealtime.ts"
    )
    const src = fs.readFileSync(hookPath, "utf8")
    assert.match(src, /applyBrokerImportedTradeToCache/)
    assert.doesNotMatch(src, /fullHistory/)
    assert.doesNotMatch(src, /invalidateTradesCache/)
    assert.match(src, /ensureTradesLoaded\(supabase, userId\)/)
  })
})
export {}
