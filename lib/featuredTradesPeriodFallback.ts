import {
  endOfDay,
  getMondayOfWeek,
  getSundayOfWeek,
  startOfDay,
} from "./tradingReports/tradingReportPeriods.ts"
import {
  pickBestPnlPost,
  pickHighestRrPost,
} from "./featuredTradesWeekLogic.ts"

export type FeaturedTradesPeriodKind =
  | "current_week"
  | "previous_week"
  | "earlier_week"
  | "monthly"

export type FeaturedTradesPeriod = {
  kind: FeaturedTradesPeriodKind
  start: Date
  end: Date
}

const MAX_WEEK_LOOKBACK = 52
const MAX_MONTH_LOOKBACK = 24

type PostRow = { pnl?: unknown; rr?: unknown; created_at?: string }

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

function rowsInRange<T extends { created_at?: string }>(
  rows: readonly T[],
  start: Date,
  end: Date
): T[] {
  const startMs = start.getTime()
  const endMs = end.getTime()
  return rows.filter((row) => {
    if (!row.created_at) return false
    const ms = new Date(row.created_at).getTime()
    return ms >= startMs && ms <= endMs
  })
}

function periodHasFeaturedTrades<T extends PostRow>(
  pnlRows: readonly T[],
  rrRows: readonly T[],
  start: Date,
  end: Date
): boolean {
  const pnl = rowsInRange(pnlRows, start, end)
  const rr = rowsInRange(rrRows, start, end)
  return pickBestPnlPost(pnl) != null || pickHighestRrPost(rr) != null
}

export function resolveFeaturedTradesPeriod(
  pnlRows: readonly PostRow[],
  rrRows: readonly PostRow[],
  now: Date = new Date()
): FeaturedTradesPeriod | null {
  const current = calendarWeekBounds(now, 0)
  if (periodHasFeaturedTrades(pnlRows, rrRows, current.start, current.end)) {
    return { kind: "current_week", ...current }
  }

  const previous = calendarWeekBounds(now, 1)
  if (periodHasFeaturedTrades(pnlRows, rrRows, previous.start, previous.end)) {
    return { kind: "previous_week", ...previous }
  }

  for (let weeksAgo = 2; weeksAgo < MAX_WEEK_LOOKBACK; weeksAgo += 1) {
    const bounds = calendarWeekBounds(now, weeksAgo)
    if (periodHasFeaturedTrades(pnlRows, rrRows, bounds.start, bounds.end)) {
      return { kind: "earlier_week", ...bounds }
    }
  }

  for (let monthsAgo = 0; monthsAgo < MAX_MONTH_LOOKBACK; monthsAgo += 1) {
    const bounds = calendarMonthBounds(now, monthsAgo)
    if (periodHasFeaturedTrades(pnlRows, rrRows, bounds.start, bounds.end)) {
      return { kind: "monthly", ...bounds }
    }
  }

  return null
}

export function featuredTradesPeriodHeading(period: FeaturedTradesPeriod): {
  sectionTitle: string
  sectionLead: string
} {
  switch (period.kind) {
    case "current_week":
      return {
        sectionTitle: "Featured Trades of the Week",
        sectionLead:
          "Discover some of the community's best trades from this calendar week.",
      }
    case "previous_week":
      return {
        sectionTitle: "Last Week's Featured Trades",
        sectionLead:
          "Top public trades from the prior calendar week — rankings are not from the current week.",
      }
    case "earlier_week": {
      const startLabel = period.start.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      })
      const endLabel = period.end.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
      })
      return {
        sectionTitle: `Featured Trades — Week of ${startLabel} – ${endLabel}`,
        sectionLead:
          "Most recent calendar week with qualifying public trades.",
      }
    }
    case "monthly": {
      const monthName = period.start.toLocaleDateString("en-US", {
        month: "long",
      })
      const year = period.start.getFullYear()
      const currentYear = new Date().getFullYear()
      return {
        sectionTitle:
          year === currentYear
            ? `${monthName}'s Featured Trades`
            : `${monthName} ${year}'s Featured Trades`,
        sectionLead:
          "Monthly highlights from public trades — not the current week.",
      }
    }
  }
}
