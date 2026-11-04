import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  pickFeaturedTradePair,
  resolveFeaturedTradesPeriod,
} from "./featuredTradesPeriodFallback.ts"

describe("featuredTradesPeriodFallback", () => {
  const now = new Date("2026-11-03T18:00:00.000Z")

  it("uses a wider window when one calendar week has the same top P&L and R:R trader", () => {
    const rows = [
      {
        id: "a",
        user_id: "u1",
        pnl: 500,
        rr: 4,
        created_at: "2026-10-27T12:00:00.000Z",
      },
      {
        id: "b",
        user_id: "u2",
        pnl: 100,
        rr: 2,
        created_at: "2026-10-28T12:00:00.000Z",
      },
      {
        id: "c",
        user_id: "u2",
        pnl: 80,
        rr: 5,
        created_at: "2026-09-15T12:00:00.000Z",
      },
    ]

    const period = resolveFeaturedTradesPeriod(rows, rows, now)
    assert.ok(period)

    const pair = pickFeaturedTradePair(rows, period!.start, period!.end)
    assert.ok(pair.bestPnl)
    assert.ok(pair.highestRr)
    assert.notEqual(String(pair.bestPnl!.user_id), String(pair.highestRr!.user_id))
  })

  it("pickFeaturedTradePair excludes the P&L winner from the R:R pool", () => {
    const rows = [
      {
        id: "a",
        user_id: "u1",
        pnl: 500,
        rr: 4,
        created_at: "2026-11-01T12:00:00.000Z",
      },
      {
        id: "b",
        user_id: "u1",
        pnl: 50,
        rr: 3,
        created_at: "2026-11-02T12:00:00.000Z",
      },
      {
        id: "c",
        user_id: "u2",
        pnl: 200,
        rr: 2.5,
        created_at: "2026-11-02T14:00:00.000Z",
      },
    ]
    const start = new Date("2026-11-01T00:00:00.000Z")
    const end = new Date("2026-11-03T23:59:59.999Z")

    const pair = pickFeaturedTradePair(rows, start, end)
    assert.equal(pair.bestPnl?.id, "a")
    assert.equal(pair.highestRr?.id, "c")
  })
})

export {}
