import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { hasStoredTradePoints, resolveTradePoints } from "./resolveTradePoints.ts"

function assertCloseTo(actual: number, expected: number, epsilon = 1e-9) {
  assert.ok(Math.abs(actual - expected) < epsilon)
}

describe("resolveTradePoints", () => {
  it("prefers stored points including negative values", () => {
    assert.equal(
      resolveTradePoints({
        points: -5.5,
        entry_price: 21255.75,
        exit_price: 21250.25,
        direction: "Long",
      }),
      -5.5
    )
  })

  it("treats zero as a stored value", () => {
    assert.equal(hasStoredTradePoints(0), true)
    assert.equal(
      resolveTradePoints({
        points: 0,
        entry_price: 100,
        exit_price: 105,
        direction: "Long",
      }),
      0
    )
  })

  it("falls back to directional calculation for long trades", () => {
    assertCloseTo(
      resolveTradePoints({
        points: null,
        entry_price: 21250.25,
        exit_price: 21255.75,
        direction: "Long",
      }) ?? NaN,
      5.5
    )
  })

  it("falls back to directional calculation for short trades", () => {
    assertCloseTo(
      resolveTradePoints({
        points: null,
        entry_price: 21255.75,
        exit_price: 21250.25,
        direction: "Short",
      }) ?? NaN,
      5.5
    )
  })
})
