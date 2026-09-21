import assert from "node:assert/strict"
import { describe, it } from "node:test"

import { analyticsModeEffective } from "./analyticsModeEffective.ts"

describe("analyticsModeEffective", () => {
  it("normalizes eval and replay aliases", () => {
    assert.equal(
      analyticsModeEffective({ tradeMode: "eval" }),
      "evaluation"
    )
    assert.equal(analyticsModeEffective({ tradeMode: "replay" }), "sim")
  })

  it("prioritizes account mode over trade fallback", () => {
    assert.equal(
      analyticsModeEffective({
        accountMode: "funded",
        tradeMode: "evaluation",
      }),
      "funded"
    )
  })

  it("uses account_type when mode missing", () => {
    assert.equal(
      analyticsModeEffective({ accountType: "live", tradeMode: "sim" }),
      "live"
    )
  })

  it("never maps unknown to live", () => {
    assert.equal(analyticsModeEffective({ tradeMode: "mystery" }), "unknown")
    assert.equal(analyticsModeEffective({}), "unknown")
  })

  it("preserves backtest", () => {
    assert.equal(analyticsModeEffective({ tradeMode: "backtest" }), "backtest")
  })
})
