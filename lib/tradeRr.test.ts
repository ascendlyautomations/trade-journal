import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  averageRrFromTrades,
  hasStoredRr,
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
