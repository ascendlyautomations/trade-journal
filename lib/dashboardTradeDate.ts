import {
  getTradingDayKey,
  resolveTradingTimeSourceForKey,
} from "./formatDate"

/** Trade fields used for dashboard date resolution (entry/exit first, then created_at). */
export type DashboardTradeDateFields = {
  created_at?: string | null
  date?: string | null
  entry_time?: string | null
  exit_time?: string | null
}

/**
 * Primary timestamp string for dashboard filters, sort, buckets, and charts.
 * Priority: entry_time → exit_time → created_at / date fallback.
 */
export function resolveDashboardTradeTimeSource(
  trade: DashboardTradeDateFields
): string | null {
  const fromEntryExit = resolveTradingTimeSourceForKey(trade)
  if (fromEntryExit) return fromEntryExit

  const fallback = trade.created_at ?? trade.date
  if (fallback == null) return null
  const raw = String(fallback).trim()
  if (!raw) return null

  const d = new Date(raw)
  if (Number.isNaN(d.getTime())) return null
  return raw
}

export function resolveDashboardTradeDate(
  trade: DashboardTradeDateFields
): Date | null {
  const src = resolveDashboardTradeTimeSource(trade)
  if (!src) return null
  const d = new Date(src)
  return Number.isNaN(d.getTime()) ? null : d
}

export function compareDashboardTradesChronological(
  a: DashboardTradeDateFields,
  b: DashboardTradeDateFields
): number {
  const ta = resolveDashboardTradeDate(a)?.getTime() ?? 0
  const tb = resolveDashboardTradeDate(b)?.getTime() ?? 0
  return ta - tb
}

/** Futures trading day key (6 PM EST rollover) from the dashboard time source. */
export function getDashboardTradingDayKey(
  trade: DashboardTradeDateFields
): string | null {
  const src = resolveDashboardTradeTimeSource(trade)
  if (!src) return null
  return getTradingDayKey(src)
}

export function tradeMatchesDashboardSelectedDate(
  trade: DashboardTradeDateFields,
  selectedDate: string
): boolean {
  if (!selectedDate.trim()) return true
  const key = getDashboardTradingDayKey(trade)
  if (!key) return false
  return key === selectedDate.trim()
}

export function tradeMatchesDashboardTimeFilter(
  trade: DashboardTradeDateFields,
  timeFilter: string,
  now: Date,
  customRangeStart: string,
  customRangeEnd: string
): boolean {
  if (timeFilter === "all") return true

  const tradeDate = resolveDashboardTradeDate(trade)
  if (!tradeDate) return false

  if (timeFilter === "daily") {
    return tradeDate.toDateString() === now.toDateString()
  }
  if (timeFilter === "weekly") {
    const weekAgo = new Date(now)
    weekAgo.setDate(now.getDate() - 7)
    return tradeDate >= weekAgo
  }
  if (timeFilter === "monthly") {
    return (
      tradeDate.getMonth() === now.getMonth() &&
      tradeDate.getFullYear() === now.getFullYear()
    )
  }
  if (timeFilter === "yearly") {
    return tradeDate.getFullYear() === now.getFullYear()
  }
  if (timeFilter === "custom") {
    if (!customRangeStart?.trim() || !customRangeEnd?.trim()) return true
    const start = new Date(customRangeStart + "T00:00:00")
    const end = new Date(customRangeEnd + "T23:59:59.999")
    return tradeDate >= start && tradeDate <= end
  }
  return true
}
