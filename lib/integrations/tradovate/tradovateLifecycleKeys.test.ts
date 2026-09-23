import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { filterPreviewsNotInBaseline } from "./tradovateLifecycleKeys.ts"
import type { TradovateImportPreviewTrade } from "./tradovateImportPreview.ts"

function preview(lifecycleKey: string): TradovateImportPreviewTrade {
  return {
    lifecycleKey,
    contractId: "4399654",
    ticker: "MNQ",
    direction: "Short",
    contracts: 1,
    entryPrice: 1,
    exitPrice: 1,
    entryTime: "2026-01-01T00:00:00.000Z",
    exitTime: "2026-01-01T00:01:00.000Z",
    points: 0,
    pnl: null,
    grossPnl: null,
    fees: 0,
  }
}

describe("tradovate lifecycle preview baseline", () => {
  it("uses sync-start snapshot so concurrent import cannot zero preview", () => {
    const previews = [
      preview("tradovate:v2:1:4399654:3"),
      preview("tradovate:v2:1:4399654:4"),
    ]
    const atStart = new Set(["tradovate:v2:1:4399654:3"])
    const eligible = filterPreviewsNotInBaseline(previews, atStart)
    assert.equal(eligible.length, 1)
    assert.equal(eligible[0]!.lifecycleKey, "tradovate:v2:1:4399654:4")
  })
})
