import { describe, it } from "node:test"
import { deriveTradeChecklistSignalsFromTrades, } from "./deriveTradeChecklistSignals.ts"
import assert from "node:assert/strict"

describe("deriveTradeChecklistSignalsFromTrades", () => {
  it("counts all trades and detects public flag", () => {
    const signals = deriveTradeChecklistSignalsFromTrades([
      { id: "1", is_public: false, mode: "live" },
      { id: "2", is_public: true, mode: "live" },
    ])
    assert.equal(signals.tradeCount, 2)
    assert.equal(signals.hasPublicTrade, true)
  })

  it("picks first private non-backtest trade in list order", () => {
    const signals = deriveTradeChecklistSignalsFromTrades([
      { id: "public", is_public: true, mode: "live" },
      { id: "backtest", is_public: false, mode: "backtest" },
      { id: "private", is_public: false, mode: "live" },
    ])
    assert.equal(signals.firstPrivateTradeId, "private")
  })

  it("returns null private trade id when only backtest privates exist", () => {
    const signals = deriveTradeChecklistSignalsFromTrades([
      { id: "bt", is_public: false, mode: "backtest" },
    ])
    assert.equal(signals.firstPrivateTradeId, null)
    assert.equal(signals.hasPublicTrade, false)
  })
})
export {}
