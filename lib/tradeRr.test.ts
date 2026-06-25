import { describe, expect, it } from "vitest"
import {
  averageRrFromTrades,
  hasStoredRr,
  parseOptionalRr,
} from "./tradeRr"

describe("hasStoredRr", () => {
  it("accepts finite numbers including zero", () => {
    expect(hasStoredRr(0)).toBe(true)
    expect(hasStoredRr(1.5)).toBe(true)
    expect(hasStoredRr("2")).toBe(true)
  })

  it("rejects null, blank, and non-numeric values", () => {
    expect(hasStoredRr(null)).toBe(false)
    expect(hasStoredRr(undefined)).toBe(false)
    expect(hasStoredRr("")).toBe(false)
    expect(hasStoredRr("   ")).toBe(false)
    expect(hasStoredRr("abc")).toBe(false)
  })
})

describe("parseOptionalRr", () => {
  it("returns null for blank input", () => {
    expect(parseOptionalRr("")).toBe(null)
    expect(parseOptionalRr("   ")).toBe(null)
    expect(parseOptionalRr(null)).toBe(null)
  })

  it("preserves zero as a real RR value", () => {
    expect(parseOptionalRr("0")).toBe(0)
    expect(parseOptionalRr(0)).toBe(0)
  })

  it("parses valid numeric strings", () => {
    expect(parseOptionalRr("1.25")).toBe(1.25)
  })
})

describe("averageRrFromTrades", () => {
  it("ignores trades without stored RR", () => {
    const avg = averageRrFromTrades([
      { rr: null },
      { rr: 2 },
      { rr: 4 },
    ])
    expect(avg).toBe(3)
  })

  it("returns null when no trades have RR", () => {
    expect(averageRrFromTrades([{ rr: null }, {}])).toBe(null)
  })

  it("includes genuine zero RR trades", () => {
    const avg = averageRrFromTrades([{ rr: 0 }, { rr: 2 }])
    expect(avg).toBe(1)
  })
})
