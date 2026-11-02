import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  buildMobileWebDashboardMetricChips,
  buildMobileWebDashboardPerformanceCards,
  lastEquityPointValue,
  mobileWebDashboardHeroTitle,
  mobileWebDashboardHourBars,
  mobileWebDashboardHourBarsHaveSignal,
  moneyTone,
} from "./mobileWebDashboard.ts"

describe("mobileWebDashboard", () => {
  it("reads the last equity point for the phone hero value", () => {
    assert.equal(lastEquityPointValue([]), null)
    assert.equal(lastEquityPointValue([{ equity: 100 }, { equity: 5900 }]), 5900)
  })

  it("titles the hero Account Value for a single live account", () => {
    assert.equal(mobileWebDashboardHeroTitle(true), "Account Value")
    assert.equal(mobileWebDashboardHeroTitle(false), "Equity")
  })

  it("builds a 24-hour bar series and detects signal", () => {
    const empty = mobileWebDashboardHourBars({})
    assert.equal(empty.length, 24)
    assert.equal(mobileWebDashboardHourBarsHaveSignal(empty), false)
    const bars = mobileWebDashboardHourBars({ 10: 2860, 11: -680 })
    assert.equal(bars[10]?.value, 2860)
    assert.equal(mobileWebDashboardHourBarsHaveSignal(bars), true)
  })

  it("maps signed values to chip tone", () => {
    assert.equal(moneyTone(1), "positive")
    assert.equal(moneyTone(-1), "negative")
    assert.equal(moneyTone(0), "neutral")
    assert.equal(moneyTone(null), "neutral")
  })

  it("keeps native KPI strip order and omits Net P&L", () => {
    const chips = buildMobileWebDashboardMetricChips({
      winRate: 62.5,
      profitFactor: 1.8,
      avgRR: 2.1,
      avgMaxRrReached: 3.4,
      totalTrades: 40,
      expectancy: 125,
    })
    assert.deepEqual(
      chips.map((chip) => chip.id),
      ["win", "pf", "rr", "maxRr", "trades", "expectancy"]
    )
    assert.equal(
      chips.some((chip) => /p&l|pnl/i.test(chip.label)),
      false
    )
  })

  it("keeps native performance card order including payouts", () => {
    const cards = buildMobileWebDashboardPerformanceCards({
      avgWin: 400,
      avgLoss: -180,
      bestTrade: 1200,
      biggestLoss: -900,
      maxDrawdown: 2100,
    })
    assert.deepEqual(
      cards.map((card) => card.id),
      ["avgWin", "avgLoss", "best", "worst", "dd", "payouts"]
    )
    assert.equal(cards[5]?.value, "—")
  })
})
