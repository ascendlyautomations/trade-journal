import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  composeAverageLoser,
  composeAverageRr,
  composeAverageWinner,
  composeProfitFactor,
  composeWinRate,
  type DailyStatsIngredients,
} from "./tradeDailyStatsMetrics.ts"

/** Mirror SQL analytics_dashboard_preset_bounds (ET civil). */
function presetBounds(asOf: string, preset: string): { start: string; end: string } {
  const end = asOf
  const [y, m, d] = asOf.split("-").map(Number)
  const pad = (n: number) => String(n).padStart(2, "0")
  switch (preset) {
    case "d7": {
      const dt = new Date(Date.UTC(y, m - 1, d - 6))
      return { start: `${dt.getUTCFullYear()}-${pad(dt.getUTCMonth() + 1)}-${pad(dt.getUTCDate())}`, end }
    }
    case "d30": {
      const dt = new Date(Date.UTC(y, m - 1, d - 29))
      return { start: `${dt.getUTCFullYear()}-${pad(dt.getUTCMonth() + 1)}-${pad(dt.getUTCDate())}`, end }
    }
    case "ytd":
      return { start: `${y}-01-01`, end }
    case "all":
      return { start: "1970-01-01", end }
    default:
      throw new Error(`invalid ${preset}`)
  }
}

describe("dashboard V3 preset bounds", () => {
  it("YTD starts Jan 1 ET civil", () => {
    assert.deepEqual(presetBounds("2026-09-21", "ytd"), {
      start: "2026-01-01",
      end: "2026-09-21",
    })
  })

  it("d7 spans 7 inclusive civil days", () => {
    assert.deepEqual(presetBounds("2026-09-21", "d7"), {
      start: "2026-09-15",
      end: "2026-09-21",
    })
  })
})

describe("dashboard V3 metric composition", () => {
  const sample: DailyStatsIngredients = {
    trade_count: 10,
    win_count: 6,
    loss_count: 4,
    breakeven_count: 0,
    net_pnl: 500,
    gross_profit: 900,
    gross_loss: -400,
    long_count: 7,
    long_pnl: 400,
    short_count: 3,
    short_pnl: 100,
    sum_rr: 12,
    rr_count: 8,
    sum_hold_seconds: 3600,
    hold_count: 10,
    largest_win: 200,
    largest_loss: -150,
  }

  it("composes win rate from trade denominator", () => {
    assert.equal(composeWinRate(sample), 0.6)
  })

  it("composes profit factor from gross sums not daily averages", () => {
    assert.equal(composeProfitFactor(sample), 900 / 400)
  })

  it("composes average winner/loser from gross/count", () => {
    assert.equal(composeAverageWinner(sample), 150)
    assert.equal(composeAverageLoser(sample), 100)
  })

  it("composes average RR from sum_rr / rr_count", () => {
    assert.equal(composeAverageRr(sample), 1.5)
  })
})
