import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  REALIZED_RR_CANNOT_EXCEED_TARGETED,
  averageRealizedRrFromTrades,
  averageTargetedRrFromTrades,
  computeActualPoints,
  computeRealizedRrFromPricesAndPlan,
  realizedRrForManualTradeSave,
  resolveRealizedRr,
  validateManualTradeRiskFields,
  validateRealizedRrAgainstTargeted,
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

describe("averageTargetedRrFromTrades", () => {
  it("averages stored targeted rr and skips missing", () => {
    const avg = averageTargetedRrFromTrades([
      { rr: 2, points: 50 },
      { rr: null, points: 40 },
      { rr: 4, points: 30 },
    ])
    assert.equal(avg, 3)
  })
})

describe("realizedRrForManualTradeSave", () => {
  it("uses targeted rr when full tp win", () => {
    assert.equal(
      realizedRrForManualTradeSave({
        full_tp: true,
        pnl: 200,
        rr: 2.5,
        points: 50,
        direction: "Long",
        entry_price: 100,
        exit_price: 101,
      }),
      2.5
    )
  })

  it("returns null on partial win without price data", () => {
    assert.equal(
      realizedRrForManualTradeSave({
        full_tp: false,
        pnl: 200,
        rr: 2,
        points: 50,
        direction: "Long",
      }),
      null
    )
  })

  it("derives loss rr from prices when full tp unchecked", () => {
    assert.equal(
      realizedRrForManualTradeSave({
        full_tp: false,
        pnl: -100,
        rr: 2.5,
        points: 50,
        direction: "Long",
        entry_price: 100,
        exit_price: 80,
      }),
      -1
    )
  })

  it("early exit win uses exit rr from prices not max", () => {
    const rr = realizedRrForManualTradeSave({
      full_tp: false,
      early_exit: true,
      pnl: 200,
      rr: 2,
      points: 50,
      direction: "Long",
      entry_price: 100,
      exit_price: 125,
    })
    assert.equal(rr, 1)
  })

  it("early exit win can use manual exit_rr", () => {
    assert.equal(
      realizedRrForManualTradeSave({
        full_tp: false,
        early_exit: true,
        pnl: 200,
        rr: 2,
        points: 50,
        exit_rr: 1,
      }),
      1
    )
  })
})

describe("validateRealizedRrAgainstTargeted", () => {
  it("rejects exit_rr above targeted", () => {
    assert.equal(
      validateRealizedRrAgainstTargeted({
        pnl: 100,
        rr: 2,
        early_exit: true,
        exit_rr: 2.5,
        points: 50,
      }),
      REALIZED_RR_CANNOT_EXCEED_TARGETED
    )
  })

  it("allows equality on full tp", () => {
    assert.equal(
      validateRealizedRrAgainstTargeted({
        pnl: 100,
        rr: 2,
        full_tp: true,
        points: 50,
      }),
      null
    )
  })

  it("allows realized below targeted", () => {
    assert.equal(
      validateRealizedRrAgainstTargeted({
        pnl: 100,
        rr: 2,
        early_exit: true,
        exit_rr: 1,
        points: 50,
      }),
      null
    )
  })
})

describe("validateManualTradeRiskFields realized cap", () => {
  it("surfaces cap on manual exit rr", () => {
    const v = validateManualTradeRiskFields({
      pnl: 100,
      pointsRaw: 50,
      targetedRrRaw: 2,
      maxRrReachedRaw: 1.5,
      earlyExit: true,
      exitRrRaw: 3,
      entryPriceRaw: null,
      exitPriceRaw: null,
      direction: "Long",
    })
    assert.equal(v.exitRr, REALIZED_RR_CANNOT_EXCEED_TARGETED)
    assert.equal(v.ok, false)
  })
})
