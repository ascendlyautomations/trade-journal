import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  LEADERBOARD_PRESET_VIEW_ORDER,
  buildLeaderboardChartDataWithFallback,
  nextLargerLeaderboardView,
  resolveLeaderboardEffectiveView,
  leaderboardTimeframeFallbackMessage,
} from "./leaderboardTimeframeFallback.ts"
import type { TradeForLeaderboard } from "./leaderboardChart.ts"

const NOW = new Date()

function trade(
  userId: string,
  pnl: number,
  daysAgo: number
): TradeForLeaderboard {
  const created = new Date(NOW.getTime() - daysAgo * 24 * 60 * 60 * 1000)
  return {
    user_id: userId,
    pnl,
    rr: 1,
    created_at: created.toISOString(),
  }
}

/** Mia wins 7D; Old wins ALL only. */
const SAMPLE_TRADES: TradeForLeaderboard[] = [
  trade("u-mia", 9000, 0),
  trade("u-alex", 1000, 2),
  trade("u-alex", 8000, 20),
  trade("u-sam", 5000, 10),
  trade("u-old", 50_000, 400),
]

describe("leaderboardTimeframeFallback", () => {
  it("orders presets smallest to largest", () => {
    assert.deepEqual(LEADERBOARD_PRESET_VIEW_ORDER, [
      "7D",
      "30D",
      "90D",
      "YTD",
      "ALL",
    ])
  })

  it("nextLarger never moves smaller or loops", () => {
    assert.equal(nextLargerLeaderboardView("7D"), "30D")
    assert.equal(nextLargerLeaderboardView("30D"), "90D")
    assert.equal(nextLargerLeaderboardView("90D"), "YTD")
    assert.equal(nextLargerLeaderboardView("YTD"), "ALL")
    assert.equal(nextLargerLeaderboardView("ALL"), null)
    assert.equal(nextLargerLeaderboardView("Custom"), "7D")
  })

  it("selected timeframe with data stays on requested view", () => {
    const resolution = resolveLeaderboardEffectiveView(
      SAMPLE_TRADES,
      "7D",
      null,
      undefined,
      "all"
    )
    assert.equal(resolution.effectiveView, "7D")
    assert.equal(resolution.usedFallback, false)
  })

  it("empty 7D falls forward to first non-empty preset", () => {
    const onlyOld: TradeForLeaderboard[] = [trade("u-old", 50_000, 400)]
    const resolution = resolveLeaderboardEffectiveView(
      onlyOld,
      "7D",
      null,
      undefined,
      "all"
    )
    assert.equal(resolution.effectiveView, "ALL")
    assert.equal(resolution.usedFallback, true)
  })

  it("all presets empty keeps requested view", () => {
    const resolution = resolveLeaderboardEffectiveView([], "7D", null, undefined, "all")
    assert.equal(resolution.effectiveView, "7D")
    assert.equal(resolution.usedFallback, false)
    const built = buildLeaderboardChartDataWithFallback(
      [],
      "7D",
      null,
      undefined,
      "all"
    )
    assert.equal(built.hasData, false)
  })

  it("ALL empty is genuine empty state", () => {
    const built = buildLeaderboardChartDataWithFallback(
      [],
      "ALL",
      null,
      undefined,
      "all"
    )
    assert.equal(built.effectiveView, "ALL")
    assert.equal(built.hasData, false)
    assert.equal(built.usedFallback, false)
  })

  it("buildLeaderboardChartDataWithFallback ranking unchanged for same view", () => {
    const direct = buildLeaderboardChartDataWithFallback(
      SAMPLE_TRADES,
      "ALL",
      null,
      undefined,
      "all"
    )
    assert.equal(direct.effectiveView, "ALL")
    assert.ok(direct.rankedTraders[0]?.userId === "u-old")
  })

  it("fallback message names requested and effective labels", () => {
    const message = leaderboardTimeframeFallbackMessage("7D", "30D")
    assert.match(message ?? "", /7 Days/)
    assert.match(message ?? "", /30 Days/)
  })

  it("multiple empty presets fall forward to first non-empty", () => {
    const onlyNinetyDay: TradeForLeaderboard[] = [trade("u-mid", 5000, 45)]
    const resolution = resolveLeaderboardEffectiveView(
      onlyNinetyDay,
      "7D",
      null,
      undefined,
      "all"
    )
    assert.equal(resolution.effectiveView, "90D")
    assert.equal(resolution.usedFallback, true)
  })

  it("Custom empty falls forward through presets", () => {
    const onlyOld: TradeForLeaderboard[] = [trade("u-old", 50_000, 400)]
    const end = NOW.toISOString().slice(0, 10)
    const start = new Date(NOW.getTime() - 5 * 24 * 60 * 60 * 1000)
      .toISOString()
      .slice(0, 10)
    const customRange = { startDate: start, endDate: end }
    const resolution = resolveLeaderboardEffectiveView(
      onlyOld,
      "Custom",
      null,
      customRange,
      "all"
    )
    assert.equal(resolution.effectiveView, "ALL")
    assert.equal(resolution.usedFallback, true)
  })

  it("fallback never moves to a smaller preset", () => {
    const resolution = resolveLeaderboardEffectiveView(
      SAMPLE_TRADES,
      "ALL",
      null,
      undefined,
      "all"
    )
    assert.equal(resolution.effectiveView, "ALL")
    assert.equal(resolution.usedFallback, false)
  })

  it("buildLeaderboardChartDataWithFallback performs one local evaluation", () => {
    const built = buildLeaderboardChartDataWithFallback(
      SAMPLE_TRADES,
      "7D",
      null,
      undefined,
      "all"
    )
    assert.equal(built.effectiveView, "7D")
    assert.ok(built.rankedTraders.length > 0)
  })

  it("manual smaller selection after fallback uses requested view", () => {
    const first = resolveLeaderboardEffectiveView(
      SAMPLE_TRADES,
      "7D",
      null,
      undefined,
      "all"
    )
    assert.equal(first.effectiveView, "7D")
    const second = resolveLeaderboardEffectiveView(
      SAMPLE_TRADES,
      "7D",
      null,
      undefined,
      "all"
    )
    assert.equal(second.requestedView, "7D")
    assert.equal(second.usedFallback, false)
  })
})
export {}
