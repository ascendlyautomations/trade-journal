import { formatShortDateEST, formatShortDateTimeEST } from "./formatDate.ts"
import { formatPnlCurrency } from "./formatMoney.ts"

function formatTradePriceValue(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—"
  const n = Number(value)
  if (!Number.isFinite(n)) return "—"
  return formatPnlCurrency(n)
}

function buildArrowRow(left: string | null, right: string | null): string | null {
  if (left && right) return `${left} → ${right}`
  return left || right || null
}

function buildPriceRow(
  showEntryPrice: boolean,
  showExitPrice: boolean,
  entryPrice: string | null,
  exitPrice: string | null
): string | null {
  const parts: string[] = []
  if (showEntryPrice && entryPrice) {
    parts.push(`Entry Price: ${entryPrice}`)
  }
  if (showExitPrice && exitPrice) {
    parts.push(`Exit Price: ${exitPrice}`)
  }
  if (parts.length === 0) return null
  return parts.join(" → ")
}

function buildDateTimeRow(
  entryRaw: string | null,
  exitRaw: string | null,
  fallbackDate: string | null | undefined
): string | null {
  const entryStamp = entryRaw
    ? formatShortDateTimeEST(entryRaw) || null
    : formatShortDateEST(fallbackDate ?? null) || null
  const exitStamp = exitRaw ? formatShortDateTimeEST(exitRaw) || null : null
  return buildArrowRow(entryStamp, exitStamp)
}

/** Local calendar date key (YYYY-MM-DD) for comparing entry/exit days. */
export function getLocalCalendarDateKey(
  value: string | Date | null | undefined
): string | null {
  if (value == null || value === "") return null
  const d = value instanceof Date ? value : new Date(String(value))
  if (Number.isNaN(d.getTime())) return null
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return `${y}-${m}-${day}`
}

export function isMultiCalendarDayTrade(
  entryTime: string | null | undefined,
  exitTime: string | null | undefined
): boolean {
  const entryKey = getLocalCalendarDateKey(entryTime)
  const exitKey = getLocalCalendarDateKey(exitTime)
  if (!entryKey || !exitKey) return false
  return entryKey !== exitKey
}

/** Format hold length; ≥24h shows days + hours only (e.g. 2d 5h, 7d 0h). */
export function formatHoldDurationSeconds(totalSeconds: number): string | null {
  if (!Number.isFinite(totalSeconds) || totalSeconds <= 0) return null

  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60

  if (hours >= 24) {
    const days = Math.floor(hours / 24)
    const remHours = hours % 24
    return `${days}d ${remHours}h`
  }

  if (hours === 0 && minutes === 0) {
    return "0m"
  }

  if (hours === 0) {
    return seconds > 0 ? `${minutes}m ${seconds}s` : `${minutes}m`
  }

  return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`
}

export function formatHoldDurationFromTimes(
  start: string | null | undefined,
  end: string | null | undefined
): string | null {
  if (!start || !end) return null
  const diff = +new Date(String(end)) - +new Date(String(start))
  if (!Number.isFinite(diff) || diff <= 0) return null
  return formatHoldDurationSeconds(Math.floor(diff / 1000))
}

export function hasTradePriceValue(value: unknown): boolean {
  if (value === null || value === undefined || value === "") return false
  return Number.isFinite(Number(value))
}

export function resolveTradeDurationLabel(trade: {
  entry_time?: string | null
  exit_time?: string | null
  duration_text?: unknown
  duration_seconds?: unknown
}): string | null {
  const rawText =
    trade.duration_text == null ? "" : String(trade.duration_text).trim()
  if (rawText) return rawText

  const seconds = trade.duration_seconds
  if (seconds !== null && seconds !== undefined && seconds !== "") {
    const n = Math.floor(Number(seconds))
    if (Number.isFinite(n) && n > 0) {
      return formatHoldDurationSeconds(n)
    }
  }

  return formatHoldDurationFromTimes(trade.entry_time, trade.exit_time)
}

function combineDateTimeAndDuration(
  dateTimeRow: string | null,
  duration: string | null
): string | null {
  if (dateTimeRow && duration) return `${dateTimeRow} • ${duration}`
  return dateTimeRow || duration || null
}

export type TradeTimingPresentation = {
  priceRow: string | null
  dateTimeRow: string | null
}

export function buildTradeTimingPresentation(trade: {
  entry_time?: string | null
  exit_time?: string | null
  entry_price?: unknown
  exit_price?: unknown
  entry?: unknown
  exit?: unknown
  date?: string | null
  created_at?: string | null
  duration_text?: unknown
  duration_seconds?: unknown
}): TradeTimingPresentation {
  const entryRaw = trade.entry_time ?? null
  const exitRaw = trade.exit_time ?? null
  const entryPriceRaw = trade.entry_price ?? trade.entry ?? null
  const exitPriceRaw = trade.exit_price ?? trade.exit ?? null
  const fallbackDate = trade.date ?? trade.created_at ?? null

  const showEntryPrice = hasTradePriceValue(entryPriceRaw)
  const showExitPrice = hasTradePriceValue(exitPriceRaw)
  const entryPrice = showEntryPrice
    ? formatTradePriceValue(entryPriceRaw)
    : null
  const exitPrice = showExitPrice ? formatTradePriceValue(exitPriceRaw) : null

  const dateTimeRow = buildDateTimeRow(entryRaw, exitRaw, fallbackDate)
  const duration = resolveTradeDurationLabel(trade)

  return {
    priceRow: buildPriceRow(
      showEntryPrice,
      showExitPrice,
      entryPrice,
      exitPrice
    ),
    dateTimeRow: combineDateTimeAndDuration(dateTimeRow, duration),
  }
}
