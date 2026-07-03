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

/** Monday 00:00 of the calendar week containing `date`. */
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

export type TradingReportPeriodBounds = {
  key: TradingReportPeriodKey
  kind: TradingReportKind
  start: Date
  end: Date
}

export function getTradingReportPeriodBounds(
  key: TradingReportPeriodKey,
  now = new Date()
): TradingReportPeriodBounds {
  const today = startOfDay(now)

  if (key === "weekly_this" || key === "weekly_last") {
    let monday = getMondayOfWeek(today)
    if (key === "weekly_last") {
      monday = new Date(monday)
      monday.setDate(monday.getDate() - 7)
    }

    const sunday = getSundayOfWeek(monday)
    const end = key === "weekly_this" ? endOfDay(now) : sunday

    return { key, kind: "weekly", start: monday, end }
  }

  if (key === "monthly_this") {
    const start = startOfDay(new Date(now.getFullYear(), now.getMonth(), 1))
    return { key, kind: "monthly", start, end: endOfDay(now) }
  }

  const start = startOfDay(new Date(now.getFullYear(), now.getMonth() - 1, 1))
  const end = endOfDay(new Date(now.getFullYear(), now.getMonth(), 0))
  return { key, kind: "monthly", start, end }
}

export function formatTradingReportDateRange(
  start: Date,
  end: Date,
  kind: TradingReportKind
): string {
  const sameDay = start.toDateString() === end.toDateString()
  if (sameDay) {
    return start.toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
    })
  }

  if (kind === "monthly" && start.getDate() === 1) {
    const monthEnd = endOfDay(
      new Date(start.getFullYear(), start.getMonth() + 1, 0)
    )
    if (end.toDateString() === monthEnd.toDateString()) {
      return start.toLocaleDateString(undefined, {
        month: "long",
        year: "numeric",
      })
    }
  }

  const startYear = start.getFullYear()
  const endYear = end.getFullYear()
  const startLabel = start.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    ...(startYear !== endYear ? { year: "numeric" } : {}),
  })
  const endLabel = end.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  })
  return `${startLabel} – ${endLabel}`
}

export function tradingReportPeriodTitle(kind: TradingReportKind): string {
  return kind === "weekly" ? "Weekly Trading Report" : "Monthly Trading Report"
}

/** Stable id for notification dedup — weekly = Monday ISO date, monthly = YYYY-MM */
export function tradingReportPeriodId(
  key: TradingReportPeriodKey,
  now = new Date()
): string {
  const { start, kind } = getTradingReportPeriodBounds(key, now)
  if (kind === "weekly") {
    return `week:${start.toISOString().slice(0, 10)}`
  }
  const month = String(start.getMonth() + 1).padStart(2, "0")
  return `month:${start.getFullYear()}-${month}`
}

export function isWeeklyReportReleaseDay(now = new Date()): boolean {
  return now.getDay() === 1
}

export function isMonthlyReportReleaseDay(now = new Date()): boolean {
  return now.getDate() === 1
}
