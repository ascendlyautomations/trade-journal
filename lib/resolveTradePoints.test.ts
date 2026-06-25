import { describe, expect, it } from "vitest"
import { hasStoredTradePoints, resolveTradePoints } from "./resolveTradePoints"

describe("resolveTradePoints", () => {
  it("prefers stored points including negative values", () => {
    expect(
      resolveTradePoints({
        points: -5.5,
        entry_price: 21255.75,
        exit_price: 21250.25,
        direction: "Long",
      })
    ).toBe(-5.5)
  })

  it("treats zero as a stored value", () => {
    expect(hasStoredTradePoints(0)).toBe(true)
    expect(
      resolveTradePoints({
        points: 0,
        entry_price: 100,
        exit_price: 105,
        direction: "Long",
      })
    ).toBe(0)
  })

  it("falls back to directional calculation for long trades", () => {
    expect(
      resolveTradePoints({
        points: null,
        entry_price: 21250.25,
        exit_price: 21255.75,
        direction: "Long",
      })
    ).toBeCloseTo(5.5)
  })

  it("falls back to directional calculation for short trades", () => {
    expect(
      resolveTradePoints({
        points: null,
        entry_price: 21255.75,
        exit_price: 21250.25,
        direction: "Short",
      })
    ).toBeCloseTo(5.5)
  })
})
