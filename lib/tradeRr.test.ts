import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  averageMaxRrReachedFromTrades,
  averageRrFromTrades,
  hasStoredRr,
  maxRrReachedForTradeSave,
  parseOptionalRr,
} from "./tradeRr.ts"

describe("hasStoredRr", () => {
  it("accepts finite numbers including zero", () => {
    assert.equal(hasStoredRr(0), true)
    assert.equal(hasStoredRr(1.5), true)
    assert.equal(hasStoredRr("2"), true)
  })

  it("rejects null, blank, and non-numeric values", () => {
    assert.equal(hasStoredRr(null), false)
    assert.equal(hasStoredRr(undefined), false)
    assert.equal(hasStoredRr(""), false)
    assert.equal(hasStoredRr("   "), false)
    assert.equal(hasStoredRr("abc"), false)
  })
})

describe("parseOptionalRr", () => {
  it("returns null for blank input", () => {
    assert.equal(parseOptionalRr(""), null)
    assert.equal(parseOptionalRr("   "), null)
    assert.equal(parseOptionalRr(null), null)
  })

  it("preserves zero as a real RR value", () => {
    assert.equal(parseOptionalRr("0"), 0)
    assert.equal(parseOptionalRr(0), 0)
  })

  it("parses valid numeric strings", () => {
    assert.equal(parseOptionalRr("1.25"), 1.25)
  })
})

describe("averageRrFromTrades", () => {
  it("ignores trades without stored RR", () => {
    const avg = averageRrFromTrades([
      { rr: null },
      { rr: 2 },
      { rr: 4 },
    ])
    assert.equal(avg, 3)
  })

  it("returns null when no trades have RR", () => {
    assert.equal(averageRrFromTrades([{ rr: null }, {}]), null)
  })

  it("includes genuine zero RR trades", () => {
    const avg = averageRrFromTrades([{ rr: 0 }, { rr: 2 }])
    assert.equal(avg, 1)
  })
})

describe("averageMaxRrReachedFromTrades", () => {
  it("ignores trades without stored max R:R", () => {
    const avg = averageMaxRrReachedFromTrades([
      { max_rr_reached: null },
      { max_rr_reached: 1.25 },
      { max_rr_reached: 2.5 },
    ])
    assert.equal(avg, 1.875)
  })

  it("returns null when no trades have max R:R", () => {
    assert.equal(averageMaxRrReachedFromTrades([{}, { max_rr_reached: "" }]), null)
  })

  it("includes genuine zero max R:R trades", () => {
    const avg = averageMaxRrReachedFromTrades([
      { max_rr_reached: 0 },
      { max_rr_reached: 2 },
    ])
    assert.equal(avg, 1)
  })
})

describe("maxRrReachedForTradeSave", () => {
  it("allows optional max R:R when P&L is positive", () => {
    assert.equal(maxRrReachedForTradeSave(100, 2), 2)
    assert.equal(maxRrReachedForTradeSave(100, null), undefined)
  })

  it("persists parsed value when P&L is zero or negative", () => {
    assert.equal(maxRrReachedForTradeSave(0, 1.5), 1.5)
    assert.equal(maxRrReachedForTradeSave(-50, null), null)
  })
})
