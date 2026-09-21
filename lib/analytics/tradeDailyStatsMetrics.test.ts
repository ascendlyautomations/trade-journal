import assert from "node:assert/strict"
import { describe, it } from "node:test"

import {
  composeAverageHoldSeconds,
  composeAverageLoser,
  composeAverageRr,
  composeAverageWinner,
  composeProfitFactor,
  composeWinRate,
  type DailyStatsIngredients,
} from "./tradeDailyStatsMetrics.ts"

const sample: DailyStatsIngredients = {
  trade_count: 4,
  win_count: 2,
  loss_count: 1,
  breakeven_count: 1,
  net_pnl: 150,
  gross_profit: 200,
  gross_loss: -50,
  long_count: 2,
  long_pnl: 100,
  short_count: 2,
  short_pnl: 50,
  sum_rr: 3,
  rr_count: 2,
  sum_hold_seconds: 600,
  hold_count: 2,
  largest_win: 120,
  largest_loss: -50,
}

describe("composed daily stats metrics", () => {
  it("win rate includes breakevens in denominator", () => {
    assert.equal(composeWinRate(sample), 0.5)
  })

  it("profit factor uses gross sums", () => {
    assert.equal(composeProfitFactor(sample), 4)
  })

  it("average winner/loser from gross ingredients", () => {
    assert.equal(composeAverageWinner(sample), 100)
    assert.equal(composeAverageLoser(sample), 50)
  })

  it("average RR and hold from sums", () => {
    assert.equal(composeAverageRr(sample), 1.5)
    assert.equal(composeAverageHoldSeconds(sample), 300)
  })
})
