import { checkInDateKey } from "@/lib/dailyCheckIn/dateKey"
import { psychologyTradeDateKey } from "@/lib/psychology/tradeDateKey"
import {
  endOfEasternDay,
  startOfEasternDay,
} from "@/lib/psychology/reports/periods"

export type YearPeriodBounds = {
  start: Date
  end: Date
}

export function getTradingYearBounds(
  year: number,
  now = new Date()
): YearPeriodBounds {
  const today = checkInDateKey(now)
  const currentYear = Number(today.slice(0, 4))
  const startKey = `${year}-01-01`
  const endKey =
    year === currentYear
      ? today
      : year < currentYear
        ? `${year}-12-31`
        : startKey
  return {
    start: startOfEasternDay(startKey),
    end: endOfEasternDay(endKey),
  }
}

export function getTradingMonthBounds(
  year: number,
  month: number,
  now = new Date()
): YearPeriodBounds {
  const today = checkInDateKey(now)
  const currentYear = Number(today.slice(0, 4))
  const currentMonth = Number(today.slice(5, 7))
  const startKey = `${year}-${String(month).padStart(2, "0")}-01`
  const next =
    month === 12
      ? `${year + 1}-01-01`
      : `${year}-${String(month + 1).padStart(2, "0")}-01`
  const last = new Date(startOfEasternDay(next).getTime() - 1)
  const lastKey = checkInDateKey(last)
  const endKey =
    year === currentYear && month === currentMonth
      ? today < lastKey
        ? today
        : lastKey
      : lastKey
  return {
    start: startOfEasternDay(startKey),
    end: endOfEasternDay(endKey),
  }
}

export function formatTradingYearDateRangeLabel(
  year: number,
  now = new Date()
): string {
  const today = checkInDateKey(now)
  const currentYear = Number(today.slice(0, 4))
  if (year !== currentYear) return String(year)
  const start = startOfEasternDay(`${year}-01-01`)
  const end = endOfEasternDay(today)
  const startLabel = start.toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
    timeZone: "America/New_York",
  })
  const endLabel = end.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "America/New_York",
  })
  const partial = !today.endsWith("-12-31")
  return `${startLabel} – ${endLabel}${partial ? " (partial)" : ""}`
}

export function monthLabel(month: number): string {
  const date = new Date(2024, month - 1, 1)
  return date.toLocaleDateString(undefined, { month: "long" })
}

export function shortMonthLabel(month: number): string {
  const date = new Date(2024, month - 1, 1)
  return date.toLocaleDateString(undefined, { month: "short" })
}

export function isBacktestTrade(trade: any): boolean {
  const mode = String(trade?.mode ?? "")
    .trim()
    .toLowerCase()
  const category = String(trade?.category ?? "").trim()
  return mode === "backtest" || category === "Backtest"
}

/** Years that contain at least one non-backtest trade (newest first). */
export function availableTradingReportYears(
  trades: any[],
  now = new Date()
): number[] {
  const years = new Set<number>()
  for (const trade of trades) {
    if (isBacktestTrade(trade)) continue
    const key = psychologyTradeDateKey(trade)
    if (!key) continue
    years.add(Number(key.slice(0, 4)))
  }
  if (years.size === 0) {
    const today = checkInDateKey(now)
    if (today) years.add(Number(today.slice(0, 4)))
  }
  return [...years].sort((a, b) => b - a)
}

export function parseYearlyReportParam(value: string): number | null {
  const trimmed = value.trim()
  if (!trimmed.startsWith("yearly:")) return null
  const year = parseInt(trimmed.slice("yearly:".length), 10)
  return Number.isFinite(year) && year > 0 ? year : null
}

export function yearlyReportParam(year: number): string {
  return `yearly:${year}`
}
