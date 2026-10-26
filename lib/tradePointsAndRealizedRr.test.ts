import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  averageRealizedRrFromTrades,
  computeActualPoints,
  computeRealizedRrFromPricesAndPlan,
  resolveRealizedRr,
  validateManualTradeRiskFields,
} from "./tradePointsAndRealizedRr.ts"

describe("computeActualPoints", () => {
  it("matches spec examples via price-derived realized R:R", () => {
    const base = {
      points: 50,
      rr: 2.5,
      direction: "Long",
      entry_price: 100,
    }
    assert.equal(
      computeActualPoints({
        ...base,
        exit_price: 98,
        realized_rr: -1,
      }),
      -20
    )
    assert.equal(
      computeActualPoints({
        ...base,
        exit_price: 101.5,
        realized_rr: 1.5,
      }),
      30
    )
    assert.equal(
      computeActualPoints({
        ...base,
        exit_price: 100,
        realized_rr: 0,
      }),
      0
    )
  })

  it("returns null when realized R:R unavailable", () => {
    assert.equal(
      computeActualPoints({ points: 50, rr: 2.5, direction: "Long" }),
      null
    )
  })
})

describe("computeRealizedRrFromPricesAndPlan", () => {
  it("derives -1R from prices and plan", () => {
    const rr = computeRealizedRrFromPricesAndPlan({
      points: 50,
      rr: 2.5,
      direction: "Long",
      entry_price: 100,
      exit_price: 80,
    })
    assert.equal(rr, -1)
  })

  it("returns null when points match actual move (legacy semantics)", () => {
    assert.equal(
      computeRealizedRrFromPricesAndPlan({
        points: 16,
        rr: 2.5,
        direction: "Long",
        entry_price: 100,
        exit_price: 116,
      }),
      null
    )
  })

  it("returns null on unit mismatch (tiny points vs huge price move)", () => {
    assert.equal(
      computeRealizedRrFromPricesAndPlan({
        points: 2,
        rr: 2,
        direction: "Long",
        entry_price: 21000,
        exit_price: 21126,
      }),
      null
    )
  })
})

describe("resolveRealizedRr inflation guard", () => {
  it("uses legacy rr when points column stored actual move", () => {
    assert.equal(
      resolveRealizedRr({
        rr: 2.4,
        points: 16,
        direction: "Long",
        entry_price: 100,
        exit_price: 116,
      }),
      2.4
    )
  })

  it("ignores absurd stored realized_rr", () => {
    assert.equal(
      resolveRealizedRr({
        realized_rr: 126,
        rr: 2.5,
        points: 16,
        direction: "Long",
        entry_price: 100,
        exit_price: 116,
      }),
      2.5
    )
  })
})

describe("resolveRealizedRr", () => {
  it("prefers stored realized_rr", () => {
    assert.equal(
      resolveRealizedRr({ realized_rr: 1.2, rr: 3, points: 10 }),
      1.2
    )
  })

  it("uses legacy rr on import rows when realized_rr missing", () => {
    assert.equal(
      resolveRealizedRr({
        rr: -0.8,
        import_source: "csv",
        points: null,
      }),
      -0.8
    )
  })
})

describe("validateManualTradeRiskFields", () => {
  it("requires max R:R when P&L is zero or negative", () => {
    assert.equal(
      validateManualTradeRiskFields({
        pnl: -100,
        pointsRaw: 50,
        targetedRrRaw: 2,
        maxRrReachedRaw: "",
      }).ok,
      false
    )
    assert.equal(
      validateManualTradeRiskFields({
        pnl: 100,
        pointsRaw: 50,
        targetedRrRaw: 2,
        maxRrReachedRaw: "",
      }).ok,
      true
    )
  })
})

describe("averageRealizedRrFromTrades", () => {
  it("ignores targeted-only rr on manual rows without realized", () => {
    const avg = averageRealizedRrFromTrades([
      { rr: 3, points: 50 },
      { realized_rr: 1, rr: 2, points: 40 },
    ])
    assert.equal(avg, 1)
  })
})
