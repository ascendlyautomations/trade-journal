import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { computeFuturesGrossPnl, sumFillFees } from "./tradeReconstruction.ts"
import { resolveEffectiveValuePerPoint } from "./futuresValuePerPointFallback.ts"

describe("broker trade P&L without Tradovate product metadata", () => {
  it("computes gross and net when valuePerPoint comes from symbol fallback", () => {
    const vpp = resolveEffectiveValuePerPoint({
      symbolRoot: "MNQ",
      contractValuePerPoint: null,
    })
    assert.equal(vpp, 2)
    const gross = computeFuturesGrossPnl("Long", 100, 110, 1, vpp!)
    assert.equal(gross, 20)
    const fees = sumFillFees(new Map(), ["1", "2"])
    assert.equal(fees, 0)
    assert.equal(gross - fees, 20)
  })

  it("still computes gross when fee map is empty", () => {
    const vpp = resolveEffectiveValuePerPoint({
      symbolRoot: "ES",
      contractValuePerPoint: null,
    })
    const gross = computeFuturesGrossPnl("Short", 5000, 4990, 2, vpp!)
    assert.equal(gross, 1000)
  })
})
