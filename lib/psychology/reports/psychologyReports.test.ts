import { describe, it } from "node:test"
import assert from "node:assert/strict"
import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { checkInDateKey } from "../../dailyCheckIn/dateKey.ts"
import { generatePsychologyReport } from "./generator.ts"
import { resolveSleepBand } from "./enrich.ts"
import { enrichPsychologyTrades } from "./enrich.ts"
import { psychologyTradeMetrics } from "./metrics.ts"
import { isBacktestTrade } from "../../tradeModeFilters.ts"
import {
  mondayOfEasternWeek,
  psychologyPeriodBounds,
  weeklyPsychologyRefs,
  monthlyPsychologyRefs,
  filterTradesForPeriod,
} from "./periods.ts"
import type { PsychologyReportTrade } from "./types.ts"

function trade(
  id: string,
  entryTime: string,
  overrides: Partial<PsychologyReportTrade> = {}
): PsychologyReportTrade {
  return {
    id,
    entryAtMs: Date.parse(entryTime),
    entry_time: entryTime,
    created_at: entryTime,
    pnl: 10,
    rr: 1.5,
    mode: "live",
    emotion: null,
    confidence: null,
    followedPlan: null,
    executionRating: null,
    ...overrides,
  }
}

function checkIn(
  date: string,
  overrides: Partial<TraderDailyCheckIn> = {}
): TraderDailyCheckIn {
  return {
    id: `c-${date}`,
    ownerProfileId: "user",
    checkInDate: date,
    sleepHours: 7.5,
    sleepQuality: 4,
    morningRating: 4,
    stressLevel: 2,
    energyLevel: 4,
    focusLevel: 4,
    notes: null,
    createdAt: `${date}T12:00:00.000Z`,
    updatedAt: `${date}T12:00:00.000Z`,
    ...overrides,
  }
}

describe("psychology report Eastern periods", () => {
  it("starts weekly reports on the Eastern Monday", () => {
    const wednesday = checkInDateKey(new Date("2026-09-02T16:00:00.000Z"))
    assert.equal(wednesday, "2026-09-02")
    assert.equal(mondayOfEasternWeek(wednesday), "2026-08-31")
    const bounds = psychologyPeriodBounds(
      { template: "weekly", periodID: "week:2026-08-31" },
      new Date("2026-09-02T16:00:00.000Z")
    )
    assert.equal(bounds.startDateKey, "2026-08-31")
    assert.equal(bounds.endDateKey, "2026-09-02")
  })

  it("builds monthly bounds for the named Eastern month", () => {
    const bounds = psychologyPeriodBounds(
      { template: "monthly", periodID: "month:2026-08" },
      new Date("2026-09-15T16:00:00.000Z")
    )
    assert.equal(bounds.startDateKey, "2026-08-01")
    assert.equal(bounds.endDateKey, "2026-08-31")
    assert.match(bounds.dateRangeLabel, /August/)
  })

  it("limits weekly and monthly catalogs from the earliest trade", () => {
    const now = new Date("2026-09-15T16:00:00.000Z")
    const weekly = weeklyPsychologyRefs("2026-09-01", now, 12)
    const monthly = monthlyPsychologyRefs("2026-08-01", now, 6)
    assert.ok(weekly.length >= 2)
    assert.equal(weekly[0]?.periodID, "week:2026-09-14")
    assert.equal(monthly[0]?.periodID, "month:2026-09")
  })
})

describe("sleep bands", () => {
  it("matches the iOS Sleep & Performance bands", () => {
    assert.equal(resolveSleepBand(4.9), "<5h")
    assert.equal(resolveSleepBand(5), "5–6h")
    assert.equal(resolveSleepBand(6), "6–7h")
    assert.equal(resolveSleepBand(7), "7–8h")
    assert.equal(resolveSleepBand(8), "8–9h")
    assert.equal(resolveSleepBand(9), "8–9h")
    assert.equal(resolveSleepBand(9.1), "9h+")
    assert.equal(resolveSleepBand(null), null)
  })
})

describe("after-loss behavior", () => {
  it("counts consecutive losses before each trade", () => {
    const trades = [
      trade("1", "2026-09-01T14:00:00.000Z", { pnl: -10 }),
      trade("2", "2026-09-01T15:00:00.000Z", { pnl: -8 }),
      trade("3", "2026-09-01T16:00:00.000Z", { pnl: 12 }),
    ]
    const enriched = enrichPsychologyTrades(trades, [])
    assert.equal(enriched[0]?.consecutiveLossesBefore, 0)
    assert.equal(enriched[1]?.consecutiveLossesBefore, 1)
    assert.equal(enriched[2]?.consecutiveLossesBefore, 2)
    assert.equal(enriched[2]?.previousTradeWasLoss, true)
  })
})

describe("discipline metrics", () => {
  it("computes followed-plan rate only from tagged trades", () => {
    const trades = [
      trade("1", "2026-09-01T14:00:00.000Z", { followedPlan: true, pnl: 20 }),
      trade("2", "2026-09-01T15:00:00.000Z", { followedPlan: false, pnl: -10 }),
      trade("3", "2026-09-01T16:00:00.000Z", { followedPlan: null, pnl: 5 }),
    ]
    const report = generatePsychologyReport(
      { template: "discipline", periodID: "rolling:90d" },
      trades,
      [],
      new Date("2026-09-02T16:00:00.000Z")
    )
    assert.equal(report.tradingPsychology.followedPlanRate, 0.5)
    const discipline = report.sections.find((section) => section.id === "discipline")
    assert.ok(discipline)
    assert.ok(discipline.metrics.some((row) => row.label === "Followed Plan"))
  })
})

describe("missing check-ins and sample size", () => {
  it("still generates a report without check-ins and does not invent averages", () => {
    const trades = [0, 1, 2, 3, 4].map((day) =>
      trade(String(day), `2026-09-0${2 + day}T14:00:00.000Z`)
    )
    const report = generatePsychologyReport(
      { template: "weekly", periodID: "week:2026-08-31" },
      trades,
      [],
      new Date("2026-09-10T16:00:00.000Z")
    )
    assert.equal(report.checkInSummary.checkInCount, 0)
    assert.equal(report.checkInSummary.averageSleepHours, null)
    assert.equal(report.sections.some((section) => section.id === "checkIn"), false)
    assert.equal(report.performance.reliability, "earlySignal")
  })

  it("marks fewer than 5 trades as insufficient", () => {
    const metrics = psychologyTradeMetrics([
      trade("1", "2026-09-01T14:00:00.000Z"),
      trade("2", "2026-09-01T15:00:00.000Z"),
    ])
    assert.equal(metrics.reliability, "insufficient")
    assert.equal(metrics.tradeCount, 2)
  })
})

describe("backtest exclusion", () => {
  it("does not treat backtest rows as report trades", () => {
    const live = trade("live", "2026-09-01T14:00:00.000Z")
    const backtest = trade("bt", "2026-09-01T15:00:00.000Z", { mode: "backtest" })
    assert.equal(isBacktestTrade(backtest), true)
    const bounds = psychologyPeriodBounds(
      { template: "weekly", periodID: "week:2026-08-31" },
      new Date("2026-09-02T16:00:00.000Z")
    )
    const filtered = filterTradesForPeriod(
      [live, backtest].filter((row) => !isBacktestTrade(row)),
      bounds
    )
    assert.deepEqual(filtered.map((row) => row.id), ["live"])
  })
})

describe("template section filters", () => {
  it("keeps only sleep-related sections on Sleep & Performance", () => {
    const trades = [0, 1, 2, 3, 4].map((day) =>
      trade(String(day), `2026-09-0${1 + day}T14:00:00.000Z`, {
        followedPlan: true,
        emotion: "Calm",
      })
    )
    const checkIns = trades.map((row) =>
      checkIn(row.entry_time.slice(0, 10), { sleepHours: 8 })
    )
    const report = generatePsychologyReport(
      { template: "sleepPerformance", periodID: "rolling:90d" },
      trades,
      checkIns,
      new Date("2026-09-10T16:00:00.000Z")
    )
    const ids = report.sections.map((section) => section.id)
    assert.ok(ids.includes("performance"))
    assert.ok(ids.includes("checkIn"))
    assert.equal(ids.includes("discipline"), false)
    assert.equal(ids.includes("afterLosses"), false)
  })
})
