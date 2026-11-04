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
  | "yearly"

export type FeaturedTradesPeriod = {
  kind: FeaturedTradesPeriodKind
  start: Date
  end: Date
}

const MAX_WEEK_LOOKBACK = 52
const MAX_MONTH_LOOKBACK = 24
const MAX_YEAR_LOOKBACK = 10

type PostRow = {
  pnl?: unknown
  rr?: unknown
  created_at?: string
  user_id?: unknown
  id?: unknown
}

export function featuredPostUserId(row: PostRow): string {
  return String(row.user_id ?? "").trim()
}

export function pickFeaturedTradePair<T extends PostRow>(
  rows: readonly T[],
  start: Date,
  end: Date
): { bestPnl: T | null; highestRr: T | null } {
  const inPeriod = rowsInRange(rows, start, end)
  const bestPnl = pickBestPnlPost(inPeriod)
  const rrPool = inPeriod.filter((row) => {
    if (!bestPnl) return true
    if (row === bestPnl) return false
    if (String(row.id ?? "") === String(bestPnl.id ?? "")) return false
    if (featuredPostUserId(row) === featuredPostUserId(bestPnl)) return false
    return true
  })
  const highestRr = pickHighestRrPost(rrPool)

  return { bestPnl, highestRr }
}

function periodQualifiesForFeaturedTrades<T extends PostRow>(
  rows: readonly T[],
  start: Date,
  end: Date
): boolean {
  const inPeriod = rowsInRange(rows, start, end)
  const bestPnl = pickBestPnlPost(inPeriod)
  const topRrOverall = pickHighestRrPost(inPeriod)
  if (!bestPnl && !topRrOverall) return false
  if (
    bestPnl &&
    topRrOverall &&
    featuredPostUserId(bestPnl) === featuredPostUserId(topRrOverall)
  ) {
    return false
  }
  return true
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

function calendarYearBounds(
  now: Date,
  yearsBeforeCurrent: number
): { start: Date; end: Date } {
  const year = now.getFullYear() - yearsBeforeCurrent
  const start = startOfDay(new Date(year, 0, 1))
  const end =
    yearsBeforeCurrent === 0
      ? endOfDay(now)
      : endOfDay(new Date(year, 11, 31))
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

export function resolveFeaturedTradesPeriod(
  rows: readonly PostRow[],
  _rrRowsUnused: readonly PostRow[] = rows,
  now: Date = new Date()
): FeaturedTradesPeriod | null {
  const tryPeriod = (
    kind: FeaturedTradesPeriodKind,
    start: Date,
    end: Date
  ): FeaturedTradesPeriod | null =>
    periodQualifiesForFeaturedTrades(rows, start, end)
      ? { kind, start, end }
      : null

  const current = calendarWeekBounds(now, 0)
  const resolvedCurrent = tryPeriod("current_week", current.start, current.end)
  if (resolvedCurrent) return resolvedCurrent

  const previous = calendarWeekBounds(now, 1)
  const resolvedPrevious = tryPeriod("previous_week", previous.start, previous.end)
  if (resolvedPrevious) return resolvedPrevious

  const previousMonth = calendarMonthBounds(now, 1)
  const resolvedPrevMonth = tryPeriod(
    "monthly",
    previousMonth.start,
    previousMonth.end
  )
  if (resolvedPrevMonth) return resolvedPrevMonth

  for (let weeksAgo = 2; weeksAgo < MAX_WEEK_LOOKBACK; weeksAgo += 1) {
    const bounds = calendarWeekBounds(now, weeksAgo)
    const resolved = tryPeriod("earlier_week", bounds.start, bounds.end)
    if (resolved) return resolved
  }

  for (let monthsAgo = 0; monthsAgo < MAX_MONTH_LOOKBACK; monthsAgo += 1) {
    const bounds = calendarMonthBounds(now, monthsAgo)
    const resolved = tryPeriod("monthly", bounds.start, bounds.end)
    if (resolved) return resolved
  }

  for (let yearsAgo = 0; yearsAgo < MAX_YEAR_LOOKBACK; yearsAgo += 1) {
    const bounds = calendarYearBounds(now, yearsAgo)
    const resolved = tryPeriod("yearly", bounds.start, bounds.end)
    if (resolved) return resolved
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
          "Public trades logged on TradeTraxs, shared from the journal with real P&L, not staged marketing picks.",
      }
    case "previous_week":
      return {
        sectionTitle: "Last Week's Featured Trades",
        sectionLead:
          "Top public trades from the prior calendar week. Rankings are not from the current week.",
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
        sectionTitle: `Featured Trades, Week of ${startLabel}, ${endLabel}`,
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
          "Monthly highlights from public trades, with distinct traders for top P&L and top R:R when both are shown.",
      }
    }
    case "yearly": {
      const year = period.start.getFullYear()
      return {
        sectionTitle: `${year}'s Featured Trades`,
        sectionLead:
          "Yearly highlights from public trades when shorter windows do not surface two distinct top traders.",
      }
    }
  }
}
