import { describe, it } from "node:test"
import assert from "node:assert/strict"
import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { enrichPsychologyTrades } from "./enrich.ts"
import { buildPsychologyAnalyticsReport } from "./engine.ts"
import { derivePsychologyGuardrails } from "./comparisons.ts"
import { formatOptionalPsychologyMoney } from "./format.ts"
import type { PsychologyReportTrade } from "./types.ts"

function trade(
  id: string,
  iso: string,
  pnl: number,
  extra: Partial<PsychologyReportTrade> = {}
): PsychologyReportTrade {
  return {
    id,
    entryAtMs: Date.parse(iso),
    entry_time: iso,
    created_at: iso,
    pnl,
    rr: null,
    emotion: null,
    confidence: null,
    followedPlan: null,
    executionRating: null,
    ...extra,
  }
}

function checkIn(
  date: string,
  extra: Partial<TraderDailyCheckIn> = {}
): TraderDailyCheckIn {
  return {
    id: `c-${date}`,
    ownerProfileId: "user",
    checkInDate: date,
    sleepHours: 8,
    sleepQuality: 4,
    morningRating: 4,
    stressLevel: 2,
    energyLevel: 4,
    focusLevel: 4,
    notes: null,
    createdAt: `${date}T12:00:00.000Z`,
    updatedAt: `${date}T12:00:00.000Z`,
    ...extra,
  }
}

function dayTrades(
  date: string,
  count: number,
  pnl: number,
  extra: Partial<PsychologyReportTrade> = {}
): PsychologyReportTrade[] {
  return Array.from({ length: count }, (_, index) =>
    trade(`${date}-${index}`, `${date}T${String(14 + (index % 6)).padStart(2, "0")}:00:00.000Z`, pnl, extra)
  )
}

describe("interpretive psychology insights", () => {
  it("states that the group which actually won performed better", () => {
    const trades = [
      ...dayTrades("2026-09-02", 8, 80, { confidence: 5 }),
      ...dayTrades("2026-09-03", 8, -40, { confidence: 1 }),
    ]
    const report = buildPsychologyAnalyticsReport(trades, [])
    const card = report.dashboardCards.find((row) => row.id === "conviction")
    assert.ok(card)
    assert.match(card.headline, /higher-conviction trades have performed better/)
    assert.doesNotMatch(card.headline, /lower-conviction trades have performed better/)
    assert.equal(report.dashboardCards.filter((row) => row.id === "conviction").length, 1)
  })

  it("reverses the conclusion when the low-conviction side is better", () => {
    const trades = [
      ...dayTrades("2026-09-02", 8, -40, { confidence: 5 }),
      ...dayTrades("2026-09-03", 8, 80, { confidence: 1 }),
    ]
    const report = buildPsychologyAnalyticsReport(trades, [])
    const card = report.dashboardCards.find((row) => row.id === "conviction")
    assert.ok(card)
    assert.match(card.headline, /lower-conviction trades have performed better/)
  })

  it("does not claim lower stress is better when high stress won", () => {
    const calm = dayTrades("2026-09-02", 8, -30)
    const stressed = dayTrades("2026-09-03", 8, 70)
    const report = buildPsychologyAnalyticsReport(calm.concat(stressed), [
      checkIn("2026-09-02", { stressLevel: 1 }),
      checkIn("2026-09-03", { stressLevel: 5 }),
    ])
    const card = report.dashboardCards.find((row) => row.id === "stress")
    assert.ok(card)
    assert.match(card.headline, /Higher-stress days have performed better/)
    assert.equal(derivePsychologyGuardrails(enrichPsychologyTrades(calm.concat(stressed), [
      checkIn("2026-09-02", { stressLevel: 1 }),
      checkIn("2026-09-03", { stressLevel: 5 }),
    ])).highStressWeaker, false)
  })

  it("recommends caution after poor sleep only when short sleep is worse", () => {
    const short = dayTrades("2026-09-02", 8, 60)
    const rested = dayTrades("2026-09-03", 8, -20)
    const checkIns = [
      checkIn("2026-09-02", { sleepHours: 4 }),
      checkIn("2026-09-03", { sleepHours: 8 }),
    ]
    const guardrails = derivePsychologyGuardrails(enrichPsychologyTrades(short.concat(rested), checkIns))
    assert.equal(guardrails.lowSleepHoursThreshold, null)

    const worseShort = derivePsychologyGuardrails(
      enrichPsychologyTrades(dayTrades("2026-09-04", 8, -50).concat(dayTrades("2026-09-05", 8, 40)), [
        checkIn("2026-09-04", { sleepHours: 4 }),
        checkIn("2026-09-05", { sleepHours: 8 }),
      ])
    )
    assert.equal(worseShort.lowSleepHoursThreshold, 6)
  })

  it("hides insights below 8 trades per side and caps the list at 3", () => {
    const small = [
      ...dayTrades("2026-09-02", 7, 80, { confidence: 5 }),
      ...dayTrades("2026-09-03", 7, -40, { confidence: 1 }),
    ]
    assert.equal(buildPsychologyAnalyticsReport(small, []).dashboardCards.length, 0)

    const many = [
      ...dayTrades("2026-09-02", 8, 100, { confidence: 5, followedPlan: true, emotion: "Calm" }),
      ...dayTrades("2026-09-03", 8, -40, { confidence: 1, followedPlan: false, emotion: "Frustrated" }),
    ]
    const report = buildPsychologyAnalyticsReport(many, [])
    assert.ok(report.dashboardCards.length <= 3)
    const ids = report.dashboardCards.map((card) => card.id)
    assert.equal(new Set(ids).size, ids.length)
  })

  it("counts unique Eastern days, not matched trades", () => {
    const trades = [
      trade("a", "2026-09-02T14:00:00.000Z", 10),
      trade("b", "2026-09-02T15:00:00.000Z", 10),
      trade("c", "2026-09-03T14:00:00.000Z", -5),
    ]
    const report = buildPsychologyAnalyticsReport(trades, [
      checkIn("2026-09-02"),
      checkIn("2026-09-03"),
    ])
    assert.equal(report.matchedDayCount, 2)
    assert.equal(report.checkInMatchedTradeCount, 3)
  })

  it("returns no insights or advanced rows for an empty journal", () => {
    const report = buildPsychologyAnalyticsReport([], [])
    assert.deepEqual(report.dashboardCards, [])
    assert.deepEqual(report.sections, [])
    assert.equal(report.matchedDayCount, 0)
  })

  it("does not invent a check-in comparison when trades have no check-ins", () => {
    const trades = dayTrades("2026-09-02", 8, 20)
    const report = buildPsychologyAnalyticsReport(trades, [])
    assert.equal(report.sections.some((section) => section.id === "sleep"), false)
    assert.equal(report.sections.some((section) => section.id === "stress"), false)
    assert.equal(report.matchedDayCount, 0)
  })

  it("does not render missing money as zero", () => {
    assert.equal(formatOptionalPsychologyMoney(null), null)
    assert.equal(formatOptionalPsychologyMoney(Number.NaN), null)
    assert.equal(formatOptionalPsychologyMoney(0), "$0")
    const missing = dayTrades("2026-09-02", 6, 0).map((row) => ({ ...row, pnl: null }))
    const missingReport = buildPsychologyAnalyticsReport(missing, [])
    assert.equal(missingReport.baseline.averagePnL, null)
    assert.equal(missingReport.baseline.expectancy, null)
    const mixed = [
      ...dayTrades("2026-09-02", 2, 10),
      ...dayTrades("2026-09-03", 2, 0).map((row) => ({ ...row, pnl: null })),
    ]
    const mixedReport = buildPsychologyAnalyticsReport(mixed, [])
    assert.equal(mixedReport.baseline.averagePnL, 10)
    assert.equal(mixedReport.baseline.winRate, 1)
  })
})
