import { describe, it } from "node:test"
import assert from "node:assert/strict"
import { getTradingDayKey } from "../formatDate.ts"
import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import {
  addCalendarDaysToDateKey,
  checkInDateKey,
  checkInHistoryStartDateKey,
} from "../dailyCheckIn/dateKey.ts"
import { buildCheckInSummary } from "./checkInSummary.ts"
import { checkInsMatchingTrades, correlateTradesToCheckIns } from "./correlate.ts"
import { buildDashboardPsychologyStats } from "./dashboardStats.ts"
import { stressAverageDisplayText } from "./display.ts"
import { psychologyTradeDateKey } from "./tradeDateKey.ts"
import {
  computePsychologyInsightsUnlockProgress,
  displayCheckInDayCountForGate,
  displayTradeCountForGate,
  PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT,
  showsPsychologyInsightsRequirement,
} from "./unlockProgress.ts"

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

function trade(id: string, entryTime: string, accountId = "acct-a") {
  return {
    id,
    account_id: accountId,
    entry_time: entryTime,
    created_at: entryTime,
    pnl: 10,
  }
}

describe("psychology Eastern date correlation", () => {
  it("joins trades to check-ins by America/New_York calendar date", () => {
    const entry = "2026-09-02T14:00:00.000Z"
    const dateKey = checkInDateKey(new Date(entry))
    const rows = correlateTradesToCheckIns(
      [trade("t1", entry)],
      [checkIn(dateKey)]
    )
    assert.equal(rows[0]?.tradeDateKey, dateKey)
    assert.equal(rows[0]?.checkIn?.id, `c-${dateKey}`)
  })

  it("does not use the 6PM Eastern trading-day rollover", () => {
    const afterSix = "2026-09-02T22:30:00.000Z"
    const instant = new Date(afterSix)
    assert.equal(psychologyTradeDateKey(trade("t1", afterSix)), "2026-09-02")
    assert.equal(getTradingDayKey(instant), "2026-09-03")
    assert.notEqual(
      psychologyTradeDateKey(trade("t1", afterSix)),
      getTradingDayKey(instant)
    )
  })
})

describe("PsychologyInsightsUnlockProgress", () => {
  it("counts distinct trading days with a check-in, not extra same-day trades", () => {
    const trades = [
      trade("1", "2026-09-02T14:00:00.000Z"),
      trade("2", "2026-09-02T15:00:00.000Z"),
      trade("3", "2026-09-03T14:00:00.000Z"),
      trade("4", "2026-09-04T14:00:00.000Z"),
    ]
    const checkIns = [
      checkIn("2026-09-02"),
      checkIn("2026-09-03"),
      checkIn("2099-01-01"),
    ]
    const progress = computePsychologyInsightsUnlockProgress(trades, checkIns)
    assert.equal(progress.tradeCount, 4)
    assert.equal(progress.tradingDayCheckInCount, 2)
    assert.equal(showsPsychologyInsightsRequirement(progress), true)
  })

  it("unlocks only at 5 trading-day check-ins and 5 trades", () => {
    const trades = [0, 1, 2, 3, 4].map((day) =>
      trade(
        String(day),
        `2026-09-0${2 + day}T14:00:00.000Z`
      )
    )
    const checkIns = trades.map((row) =>
      checkIn(psychologyTradeDateKey(row))
    )
    const progress = computePsychologyInsightsUnlockProgress(trades, checkIns)
    assert.equal(progress.tradeCount, PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT)
    assert.equal(
      progress.tradingDayCheckInCount,
      PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT
    )
    assert.equal(showsPsychologyInsightsRequirement(progress), false)
    assert.equal(
      displayCheckInDayCountForGate(progress),
      PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT
    )
    assert.equal(
      displayTradeCountForGate(progress),
      PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT
    )
  })

  it("ignores check-ins on days outside the filtered trade set", () => {
    const filtered = [trade("a", "2026-09-02T14:00:00.000Z", "acct-a")]
    const checkIns = [checkIn("2026-09-02"), checkIn("2026-09-03")]
    const progress = computePsychologyInsightsUnlockProgress(filtered, checkIns)
    assert.equal(progress.tradeCount, 1)
    assert.equal(progress.tradingDayCheckInCount, 1)
  })
})

describe("dashboard filter behavior", () => {
  it("timeframe subsets change unlock counts from the same cached check-ins", () => {
    const trades = [
      trade("early", "2026-09-02T14:00:00.000Z"),
      trade("late", "2026-09-10T14:00:00.000Z"),
    ]
    const checkIns = [checkIn("2026-09-02"), checkIn("2026-09-10")]
    const thisWeek = trades.filter((row) =>
      row.entry_time.startsWith("2026-09-10")
    )
    const all = computePsychologyInsightsUnlockProgress(trades, checkIns)
    const filtered = computePsychologyInsightsUnlockProgress(thisWeek, checkIns)
    assert.equal(all.tradingDayCheckInCount, 2)
    assert.equal(all.tradeCount, 2)
    assert.equal(filtered.tradingDayCheckInCount, 1)
    assert.equal(filtered.tradeCount, 1)
  })

  it("account filters change unlock counts without changing stored check-ins", () => {
    const trades = [
      trade("a1", "2026-09-02T14:00:00.000Z", "acct-a"),
      trade("a2", "2026-09-03T14:00:00.000Z", "acct-a"),
      trade("b1", "2026-09-04T14:00:00.000Z", "acct-b"),
    ]
    const checkIns = [
      checkIn("2026-09-02"),
      checkIn("2026-09-03"),
      checkIn("2026-09-04"),
    ]
    const accountA = trades.filter((row) => row.account_id === "acct-a")
    const all = computePsychologyInsightsUnlockProgress(trades, checkIns)
    const filtered = computePsychologyInsightsUnlockProgress(accountA, checkIns)
    assert.equal(all.tradingDayCheckInCount, 3)
    assert.equal(all.tradeCount, 3)
    assert.equal(filtered.tradingDayCheckInCount, 2)
    assert.equal(filtered.tradeCount, 2)
    assert.equal(checkIns.length, 3)
  })
})

describe("check-in summary", () => {
  it("averages only present fields and does not invert stress", () => {
    const summary = buildCheckInSummary([
      checkIn("2026-09-02", { sleepHours: 6, focusLevel: 3, stressLevel: 1 }),
      checkIn("2026-09-03", { sleepHours: 8, focusLevel: 5, stressLevel: 3 }),
      checkIn("2026-09-04", { sleepHours: null, focusLevel: null, stressLevel: 2 }),
    ])
    assert.equal(summary.checkInCount, 3)
    assert.equal(summary.averageSleepHours, 7)
    assert.equal(summary.averageFocus, 4)
    assert.equal(summary.averageStress, 2)
    assert.equal(stressAverageDisplayText(2), "2.0/5 · Slightly Stressed")
    assert.equal(stressAverageDisplayText(1), "1.0/5 · Calm")
  })

  it("hides averages until the iOS unlock gate is met", () => {
    const trades = [trade("1", "2026-09-02T14:00:00.000Z")]
    const stats = buildDashboardPsychologyStats(trades, [checkIn("2026-09-02")])
    assert.equal(stats.showMetrics, false)
    assert.equal(stats.summary.averageSleepHours, null)
    assert.equal(stats.summary.checkInCount, 0)
  })

  it("uses matched check-ins for averages after unlock", () => {
    const trades = [0, 1, 2, 3, 4].map((day) =>
      trade(String(day), `2026-09-0${2 + day}T14:00:00.000Z`)
    )
    const checkIns = [
      ...trades.map((row) => checkIn(psychologyTradeDateKey(row), { sleepHours: 8 })),
      checkIn("2026-08-01", { sleepHours: 3 }),
    ]
    const stats = buildDashboardPsychologyStats(trades, checkIns)
    assert.equal(stats.showMetrics, true)
    assert.equal(stats.summary.checkInCount, 5)
    assert.equal(stats.summary.averageSleepHours, 8)
    assert.equal(checkInsMatchingTrades(trades, checkIns).length, 5)
  })
})

describe("check-in history window", () => {
  it("starts 89 Eastern calendar days before today", () => {
    const now = new Date("2026-09-30T16:00:00.000Z")
    const today = checkInDateKey(now)
    assert.equal(
      checkInHistoryStartDateKey(90, now),
      addCalendarDaysToDateKey(today, -89)
    )
  })
})
