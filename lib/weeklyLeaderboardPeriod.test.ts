import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { resolveWeeklyLeaderboardPeriod } from "./weeklyLeaderboardPeriod.ts"
import type { TradeForLeaderboard } from "./leaderboardChart.ts"
import {
  endOfDay,
  getMondayOfWeek,
  getSundayOfWeek,
  startOfDay,
} from "./tradingReports/tradingReportPeriods.ts"

function tradeAt(userId: string, createdAt: Date, pnl = 100): TradeForLeaderboard {
  return { user_id: userId, pnl, rr: 2, created_at: createdAt.toISOString() }
}

function weekBounds(now: Date, weeksBeforeCurrent: number) {
  const thisMonday = getMondayOfWeek(startOfDay(now))
  const monday = new Date(thisMonday)
  monday.setDate(thisMonday.getDate() - 7 * weeksBeforeCurrent)
  const start = startOfDay(monday)
  const end =
    weeksBeforeCurrent === 0 ? endOfDay(now) : getSundayOfWeek(monday)
  return { start, end }
}

describe("resolveWeeklyLeaderboardPeriod", () => {
  it("prefers current week, then previous week, then monthly", () => {
    const now = new Date("2026-03-18T15:00:00.000Z")
    const prev = weekBounds(now, 1)
    const trades: TradeForLeaderboard[] = [
      tradeAt("prev-a", new Date(prev.start.getTime() + 60_000)),
      tradeAt("prev-b", new Date(prev.start.getTime() + 120_000), 250),
    ]

    const resolved = resolveWeeklyLeaderboardPeriod(trades, now)
    assert.equal(resolved?.kind, "previous_week")
  })

  it("skips a week with only one qualifying trader card", () => {
    const now = new Date("2026-03-18T15:00:00.000Z")
    const prev = weekBounds(now, 1)
    const monthStart = new Date(now.getFullYear(), now.getMonth() - 1, 5)
    const trades: TradeForLeaderboard[] = [
      tradeAt("solo", new Date(prev.start.getTime() + 60_000)),
      tradeAt("month-a", monthStart, 400),
      tradeAt("month-b", new Date(monthStart.getTime() + 86_400_000), 120),
    ]

    const resolved = resolveWeeklyLeaderboardPeriod(trades, now)
    assert.equal(resolved?.kind, "monthly")
  })

  it("returns null when no qualifying trades exist", () => {
    const now = new Date("2026-03-18T15:00:00.000Z")
    assert.equal(resolveWeeklyLeaderboardPeriod([], now), null)
  })
})
