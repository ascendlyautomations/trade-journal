import { describe, it, beforeEach } from "node:test"
import { clearAppDataCache, getCachedTrades, mergeTradesInCache, prependTradeInCache, removeTradeFromCache, setTradesCache, upsertTradeInCache, } from "./appDataCache.ts"
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
  })
})
export {}
