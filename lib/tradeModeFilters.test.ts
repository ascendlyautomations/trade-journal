import assert from "node:assert/strict"
import test from "node:test"
import { excludeBacktestTrades, isBacktestTrade } from "./tradeModeFilters"

test("isBacktestTrade matches mode", () => {
  assert.equal(isBacktestTrade({ mode: "backtest", account_type: "live" }), true)
})

test("isBacktestTrade matches account_type only", () => {
  assert.equal(isBacktestTrade({ mode: "live", account_type: "backtest" }), true)
})

test("isBacktestTrade rejects live trades", () => {
  assert.equal(isBacktestTrade({ mode: "live", account_type: "funded" }), false)
})

test("excludeBacktestTrades keeps non-backtest rows", () => {
  const rows = [
    { id: "1", mode: "live" },
    { id: "2", mode: "backtest" },
    { id: "3", account_type: "backtest" },
    { id: "4", mode: "funded", account_type: "funded" },
  ]
  assert.deepEqual(excludeBacktestTrades(rows).map((r) => r.id), ["1", "4"])
})
