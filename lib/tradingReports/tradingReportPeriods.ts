import { addCalendarDaysToDateKey, checkInDateKey } from "../dailyCheckIn/dateKey"
import {
  endOfEasternDay,
  mondayOfEasternWeek,
  psychologyReportDateRangeLabel,
  startOfEasternDay,
} from "../psychology/reports/periods"
import type { TradingReportKind, TradingReportPeriodKey } from "./tradingReportTypes"

export const TRADING_REPORT_PERIOD_OPTIONS: ReadonlyArray<{
  key: TradingReportPeriodKey
  label: string
  kind: TradingReportKind
}> = [
  { key: "weekly_this", label: "This Week", kind: "weekly" },
  { key: "weekly_last", label: "Last Week", kind: "weekly" },
  { key: "monthly_this", label: "This Month", kind: "monthly" },
  { key: "monthly_last", label: "Last Month", kind: "monthly" },
]

/** Device-local helpers kept for callers that are not report windows. */
export function getMondayOfWeek(date: Date): Date {
  const monday = startOfDay(date)
  const day = monday.getDay()
  const diff = day === 0 ? -6 : 1 - day
  monday.setDate(monday.getDate() + diff)
  return monday
}

export function getSundayOfWeek(monday: Date): Date {
  const sunday = new Date(monday)
  sunday.setDate(monday.getDate() + 6)
  return endOfDay(sunday)
}

export function startOfDay(date: Date): Date {
  const next = new Date(date)
  next.setHours(0, 0, 0, 0)
  return next
}

export function endOfDay(date: Date): Date {
  const next = new Date(date)
  next.setHours(23, 59, 59, 999)
  return next
}

function lastEasternDayOfMonth(year: number, month: number): string {
  const next =
    month === 12
      ? `${year + 1}-01-01`
      : `${year}-${String(month + 1).padStart(2, "0")}-01`
  return addCalendarDaysToDateKey(next, -1)
}

function boundsFromKeys(
  key: TradingReportPeriodKey,
  kind: TradingReportKind,
  startKey: string,
  endKey: string,
  naturalEndKey: string
): TradingReportPeriodBounds {
  return {
    key,
    kind,
    start: startOfEasternDay(startKey),
    end: endOfEasternDay(endKey),
    startKey,
    endKey,
    partial: endKey < naturalEndKey,
  }
}

export type TradingReportPeriodBounds = {
  key: TradingReportPeriodKey
  kind: TradingReportKind
  start: Date
  end: Date
  /** Eastern calendar date, inclusive. */
  startKey: string
  endKey: string
  /** Current week or month has not reached its last Eastern day. */
  partial: boolean
}

/** Monday–Sunday or calendar month in America/New_York. Current periods end today. */
export function getTradingReportPeriodBounds(
  key: TradingReportPeriodKey,
  now = new Date()
): TradingReportPeriodBounds {
  const today = checkInDateKey(now)

  if (key === "weekly_this" || key === "weekly_last") {
    let monday = mondayOfEasternWeek(today)
    if (key === "weekly_last") monday = addCalendarDaysToDateKey(monday, -7)
    const sunday = addCalendarDaysToDateKey(monday, 6)
    const endKey = key === "weekly_this" && today < sunday ? today : sunday
    return boundsFromKeys(key, "weekly", monday, endKey, sunday)
  }

  const [year, month] = today.split("-").map(Number)
  if (key === "monthly_this") {
    const startKey = `${year}-${String(month).padStart(2, "0")}-01`
    const last = lastEasternDayOfMonth(year, month)
    const endKey = today < last ? today : last
    return boundsFromKeys(key, "monthly", startKey, endKey, last)
  }

  const prevMonth = month === 1 ? 12 : month - 1
  const prevYear = month === 1 ? year - 1 : year
  const startKey = `${prevYear}-${String(prevMonth).padStart(2, "0")}-01`
  const last = lastEasternDayOfMonth(prevYear, prevMonth)
  return boundsFromKeys(key, "monthly", startKey, last, last)
}

/**
 * Same elapsed Eastern days last week or last month.
 * Completed periods have no prior-window comparison.
 */
export function comparablePriorReportBounds(
  key: TradingReportPeriodKey,
  now = new Date()
): TradingReportPeriodBounds | null {
  if (key !== "weekly_this" && key !== "monthly_this") return null
  const current = getTradingReportPeriodBounds(key, now)

  if (key === "weekly_this") {
    const priorMonday = addCalendarDaysToDateKey(current.startKey, -7)
    let elapsed = 0
    let cursor = current.startKey
    while (cursor < current.endKey && elapsed < 7) {
      cursor = addCalendarDaysToDateKey(cursor, 1)
      elapsed += 1
    }
    const priorEnd = addCalendarDaysToDateKey(priorMonday, elapsed)
    const sunday = addCalendarDaysToDateKey(priorMonday, 6)
    return boundsFromKeys("weekly_last", "weekly", priorMonday, priorEnd, sunday)
  }

  const [year, month, day] = current.endKey.split("-").map(Number)
  const prevMonth = month === 1 ? 12 : month - 1
  const prevYear = month === 1 ? year - 1 : year
  const startKey = `${prevYear}-${String(prevMonth).padStart(2, "0")}-01`
  const last = lastEasternDayOfMonth(prevYear, prevMonth)
  const endDay = Math.min(day, Number(last.slice(8)))
  const endKey = `${prevYear}-${String(prevMonth).padStart(2, "0")}-${String(endDay).padStart(2, "0")}`
  return boundsFromKeys("monthly_last", "monthly", startKey, endKey, last)
}

export function formatTradingReportDateRange(
  start: Date,
  end: Date,
  kind: TradingReportKind,
  partial = false
): string {
  const startKey = checkInDateKey(start)
  const endKey = checkInDateKey(end)
  const label = psychologyReportDateRangeLabel(startKey, endKey, kind)
  return partial ? `${label} (partial)` : label
}

export function tradingReportPeriodTitle(kind: TradingReportKind): string {
  return kind === "weekly" ? "Weekly Trading Report" : "Monthly Trading Report"
}

/** Stable id for notification dedup — weekly = Monday ISO date, monthly = YYYY-MM */
export function tradingReportPeriodId(
  key: TradingReportPeriodKey,
  now = new Date()
): string {
  const { startKey, kind } = getTradingReportPeriodBounds(key, now)
  if (kind === "weekly") return `week:${startKey}`
  return `month:${startKey.slice(0, 7)}`
}

const WEEK_PERIOD_ID = /^week:(\d{4}-\d{2}-\d{2})$/

/** Monday `YYYY-MM-DD` from `week:YYYY-MM-DD`, or null when it is not an Eastern Monday. */
export function parseTradingReportWeekPeriodId(
  value: string | null | undefined
): string | null {
  if (!value) return null
  const match = WEEK_PERIOD_ID.exec(value.trim())
  if (!match) return null
  const monday = match[1]
  if (mondayOfEasternWeek(monday) !== monday) return null
  return monday
}

/**
 * Eastern Monday–Sunday identified by `week:YYYY-MM-DD`.
 * While that week is still in progress, the end date is today.
 */
export function absoluteTradingWeekBounds(
  mondayKey: string,
  now = new Date()
): TradingReportPeriodBounds {
  const sunday = addCalendarDaysToDateKey(mondayKey, 6)
  const today = checkInDateKey(now)
  const inProgress = today >= mondayKey && today < sunday
  const endKey = inProgress ? today : sunday
  return boundsFromKeys(
    inProgress ? "weekly_this" : "weekly_last",
    "weekly",
    mondayKey,
    endKey,
    sunday
  )
}

/** Saturday announcement: the Eastern week that contains today, Monday through today. */
export function saturdayCurrentWeekReport(now = new Date()): {
  periodId: string
  startKey: string
  endKey: string
  href: string
} {
  const bounds = getTradingReportPeriodBounds("weekly_this", now)
  const periodId = `week:${bounds.startKey}`
  return {
    periodId,
    startKey: bounds.startKey,
    endKey: bounds.endKey,
    href: `/dashboard?report=${encodeURIComponent(periodId)}`,
  }
}

export function isWeeklyReportReleaseDay(now = new Date()): boolean {
  const today = checkInDateKey(now)
  return mondayOfEasternWeek(today) === today
}

export function isMonthlyReportReleaseDay(now = new Date()): boolean {
  return checkInDateKey(now).endsWith("-01")
}
