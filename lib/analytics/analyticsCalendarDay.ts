/**
 * TypeScript mirror of SQL `analytics_calendar_day` / `analytics_legacy_trading_day_key`.
 * Keep in sync with supabase/migrations/20260921120000_trade_daily_stats_analytical_foundation.sql
 */

import { getTradingDayKey, parseDateLike } from "../formatDate.ts"

const EST = "America/New_York"

export function analyticsParseTradeTimestamp(
  raw: string | null | undefined
): Date | null {
  return parseDateLike(raw ?? null)
}

/** Normal analytics calendar day — ET civil date, no 18:00 rollover. */
export function analyticsCalendarDay(input: {
  entryTime?: string | null
  exitTime?: string | null
  createdAt?: string | Date | null
}): string | null {
  const instant =
    analyticsParseTradeTimestamp(input.entryTime) ??
    analyticsParseTradeTimestamp(input.exitTime) ??
    parseDateLike(input.createdAt ?? null)
  if (!instant) return null

  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: EST,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(instant)

  const y = parts.find((p) => p.type === "year")?.value
  const m = parts.find((p) => p.type === "month")?.value
  const d = parts.find((p) => p.type === "day")?.value
  if (!y || !m || !d) return null
  return `${y}-${m}-${d}`
}

/** Legacy 18:00 ET trading day (Calendar / prop-firm) — shadow comparison only. */
export function analyticsLegacyTradingDayKey(input: {
  entryTime?: string | null
  exitTime?: string | null
  createdAt?: string | Date | null
}): string | null {
  const instant =
    analyticsParseTradeTimestamp(input.entryTime) ??
    analyticsParseTradeTimestamp(input.exitTime) ??
    parseDateLike(input.createdAt ?? null)
  if (!instant) return null
  return getTradingDayKey(instant)
}

/** Realized sort instant: exit → entry → created_at */
export function analyticsRealizedSortMs(input: {
  entryTime?: string | null
  exitTime?: string | null
  createdAt?: string | Date | null
}): number | null {
  const instant =
    analyticsParseTradeTimestamp(input.exitTime) ??
    analyticsParseTradeTimestamp(input.entryTime) ??
    parseDateLike(input.createdAt ?? null)
  return instant?.getTime() ?? null
}
