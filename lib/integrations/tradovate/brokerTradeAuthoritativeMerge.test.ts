import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { mergeBrokerTradeFinancialFields } from "./brokerTradeAuthoritativeMerge.ts"

describe("brokerTradeAuthoritativeMerge", () => {
  it("keeps existing pnl when incoming calculation is null", () => {
    const merged = mergeBrokerTradeFinancialFields({
      existingPnL: -17,
      existingTicker: "MNQ",
      incomingPnL: null,
      incomingTicker: "4399654",
    })
    assert.equal(merged.finalPnL, -17)
    assert.equal(merged.finalTicker, "MNQ")
    assert.match(merged.decision, /keep_existing_pnl_over_null_incoming/)
    assert.match(merged.decision, /keep_existing_ticker/)
  })

  it("accepts incoming pnl when existing is null", () => {
    const merged = mergeBrokerTradeFinancialFields({
      existingPnL: null,
      existingTicker: "4399654",
      incomingPnL: 22,
      incomingTicker: "MNQ",
    })
    assert.equal(merged.finalPnL, 22)
    assert.equal(merged.finalTicker, "MNQ")
  })

  it("allows broker correction when both pnl values are present", () => {
    const merged = mergeBrokerTradeFinancialFields({
      existingPnL: -17,
      existingTicker: "MNQ",
      incomingPnL: -16.5,
      incomingTicker: "MNQ",
    })
    assert.equal(merged.finalPnL, -16.5)
    assert.equal(merged.finalTicker, "MNQ")
  })
})
