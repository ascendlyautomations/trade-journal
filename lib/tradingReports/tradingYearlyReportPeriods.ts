import { resolveDashboardTradeDate } from "@/lib/dashboardTradeDate"
import { endOfDay, startOfDay } from "./tradingReportPeriods"

export type YearPeriodBounds = {
  start: Date
  end: Date
}

export function getTradingYearBounds(
  year: number,
  now = new Date()
): YearPeriodBounds {
  const start = startOfDay(new Date(year, 0, 1))
  const currentYear = now.getFullYear()
  let end: Date
  if (year === currentYear) {
    end = endOfDay(now)
  } else if (year < currentYear) {
    end = endOfDay(new Date(year, 11, 31))
  } else {
    end = endOfDay(start)
  }
  return { start, end }
}

export function getTradingMonthBounds(
  year: number,
  month: number,
  now = new Date()
): YearPeriodBounds {
  const start = startOfDay(new Date(year, month - 1, 1))
  const currentYear = now.getFullYear()
  const currentMonth = now.getMonth() + 1
  let end: Date
  if (year === currentYear && month === currentMonth) {
    end = endOfDay(now)
  } else {
    end = endOfDay(new Date(year, month, 0))
  }
  return { start, end }
}

export function formatTradingYearDateRangeLabel(
  year: number,
  now = new Date()
): string {
  const bounds = getTradingYearBounds(year, now)
  if (year === now.getFullYear()) {
    const startLabel = bounds.start.toLocaleDateString(undefined, {
      month: "long",
      year: "numeric",
    })
    const endLabel = bounds.end.toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
    })
    return `${startLabel} – ${endLabel}`
  }
  return String(year)
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
    const date = resolveDashboardTradeDate(trade)
    if (!date) continue
    years.add(date.getFullYear())
  }
  if (years.size === 0 && now.getFullYear() > 0) {
    years.add(now.getFullYear())
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
