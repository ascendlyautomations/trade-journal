import type { TradeForLeaderboard } from "./leaderboardChart.ts"
import { pickWeeklyTopPerformersInRange } from "./exploreWeeklyTopPerformersPick.ts"
import {
  endOfDay,
  getMondayOfWeek,
  getSundayOfWeek,
  startOfDay,
} from "./tradingReports/tradingReportPeriods.ts"

export type WeeklyLeaderboardPeriodKind =
  | "current_week"
  | "previous_week"
  | "earlier_week"
  | "monthly"

export type WeeklyLeaderboardPeriod = {
  kind: WeeklyLeaderboardPeriodKind
  start: Date
  end: Date
}

const MAX_WEEK_LOOKBACK = 52
const MAX_MONTH_LOOKBACK = 24

export function filterTradesForLeaderboardDateRange(
  trades: TradeForLeaderboard[],
  start: Date,
  end: Date
): TradeForLeaderboard[] {
  const startMs = start.getTime()
  const endMs = end.getTime()
  return trades.filter((trade) => {
    if (!trade?.created_at || !trade.user_id) return false
    const ms = new Date(trade.created_at).getTime()
    return ms >= startMs && ms <= endMs
  })
}

function periodHasQualifyingTraders(
  trades: TradeForLeaderboard[],
  start: Date,
  end: Date
): boolean {
  return pickWeeklyTopPerformersInRange(trades, start, end).length > 0
}

function calendarWeekBounds(
  now: Date,
  weeksBeforeCurrent: number
): { start: Date; end: Date } {
  const thisMonday = getMondayOfWeek(startOfDay(now))
  const monday = new Date(thisMonday)
  monday.setDate(thisMonday.getDate() - 7 * weeksBeforeCurrent)
  const start = startOfDay(monday)
  const end =
    weeksBeforeCurrent === 0
      ? endOfDay(now)
      : getSundayOfWeek(monday)
  return { start, end }
}

function calendarMonthBounds(
  now: Date,
  monthsBeforeCurrent: number
): { start: Date; end: Date } {
  const start = startOfDay(
    new Date(now.getFullYear(), now.getMonth() - monthsBeforeCurrent, 1)
  )
  const end =
    monthsBeforeCurrent === 0
      ? endOfDay(now)
      : endOfDay(
          new Date(now.getFullYear(), now.getMonth() - monthsBeforeCurrent + 1, 0)
        )
  return { start, end }
}

/**
 * Resolves the best available leaderboard window when the current week is empty.
 * Priority: this week → last week → earlier weeks → recent calendar months.
 */
export function resolveWeeklyLeaderboardPeriod(
  trades: TradeForLeaderboard[],
  now: Date = new Date()
): WeeklyLeaderboardPeriod | null {
  const current = calendarWeekBounds(now, 0)
  if (periodHasQualifyingTraders(trades, current.start, current.end)) {
    return { kind: "current_week", ...current }
  }

  const previous = calendarWeekBounds(now, 1)
  if (periodHasQualifyingTraders(trades, previous.start, previous.end)) {
    return { kind: "previous_week", ...previous }
  }

  for (let weeksAgo = 2; weeksAgo < MAX_WEEK_LOOKBACK; weeksAgo += 1) {
    const bounds = calendarWeekBounds(now, weeksAgo)
    if (periodHasQualifyingTraders(trades, bounds.start, bounds.end)) {
      return { kind: "earlier_week", ...bounds }
    }
  }

  for (let monthsAgo = 0; monthsAgo < MAX_MONTH_LOOKBACK; monthsAgo += 1) {
    const bounds = calendarMonthBounds(now, monthsAgo)
    if (periodHasQualifyingTraders(trades, bounds.start, bounds.end)) {
      return { kind: "monthly", ...bounds }
    }
  }

  return null
}

function formatWeekHeadingRange(start: Date, end: Date): string {
  const startYear = start.getFullYear()
  const endYear = end.getFullYear()
  const startLabel = start.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    ...(startYear !== endYear ? { year: "numeric" } : {}),
  })
  const endLabel = end.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  })
  return `${startLabel} – ${endLabel}`
}

export function weeklyLeaderboardDisplayCopy(period: WeeklyLeaderboardPeriod): {
  title: string
  subtitle: string
  isHistoricalPeriod: boolean
} {
  switch (period.kind) {
    case "current_week":
      return {
        title: "Top Performers This Week",
        subtitle:
          "Calendar week rankings from public trades (all accounts)",
        isHistoricalPeriod: false,
      }
    case "previous_week":
      return {
        title: "Last Week's Top Traders",
        subtitle:
          "Public leaderboard metrics from the prior calendar week (all accounts)",
        isHistoricalPeriod: true,
      }
    case "earlier_week":
      return {
        title: `Top Traders — Week of ${formatWeekHeadingRange(period.start, period.end)}`,
        subtitle:
          "Most recent calendar week with qualifying public trades (all accounts)",
        isHistoricalPeriod: true,
      }
    case "monthly": {
      const monthName = period.start.toLocaleDateString("en-US", {
        month: "long",
      })
      const year = period.start.getFullYear()
      const currentYear = new Date().getFullYear()
      const title =
        year === currentYear
          ? `${monthName}'s Top Traders`
          : `${monthName} ${year}'s Top Traders`
      return {
        title,
        subtitle:
          "Monthly public leaderboard rankings from public trades (all accounts)",
        isHistoricalPeriod: true,
      }
    }
  }
}
