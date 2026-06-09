/** Shared helpers for Input Trade entry/exit datetime fields. */

import { formatHoldDurationFromTimes } from "./tradeTimingDisplay.ts"

export function getESTDate(): string {
  const now = new Date()
  const est = new Date(
    now.toLocaleString("en-US", { timeZone: "America/New_York" })
  )
  const y = est.getFullYear()
  const m = String(est.getMonth() + 1).padStart(2, "0")
  const d = String(est.getDate()).padStart(2, "0")
  return `${y}-${m}-${d}`
}

/** HTML date input value (YYYY-MM-DD) from ISO or date string. */
export function toDateInputValue(raw: unknown): string {
  if (raw == null || raw === "") return ""
  const s = String(raw).trim()
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s
  const d = new Date(s)
  if (!Number.isNaN(d.getTime())) {
    const y = d.getFullYear()
    const m = String(d.getMonth() + 1).padStart(2, "0")
    const day = String(d.getDate()).padStart(2, "0")
    return `${y}-${m}-${day}`
  }
  return ""
}

/** HTML time input value (HH:MM) from ISO or time-only string. */
export function toTimeInputValue(raw: unknown): string {
  if (raw == null || raw === "") return ""
  const s = String(raw).trim()
  if (/^\d{2}:\d{2}$/.test(s)) return s
  if (/^\d{1,2}:\d{2}/.test(s)) {
    const parts = s.slice(0, 5).split(":")
    return `${String(Number(parts[0])).padStart(2, "0")}:${parts[1] || "00"}`
  }
  const d = new Date(s)
  if (!Number.isNaN(d.getTime())) {
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`
  }
  return ""
}

/** Combine date (YYYY-MM-DD) + time (HH:MM) into ISO for DB storage. */
export function buildDateTime(
  date: string | null | undefined,
  time: string | null | undefined
): string | null {
  if (!date || !time) return null
  const dateStr = String(date).trim()
  const timeStr = String(time).trim()
  if (!dateStr || !timeStr) return null
  const parsed = new Date(`${dateStr} ${timeStr}`)
  if (Number.isNaN(parsed.getTime())) return null
  return parsed.toISOString()
}

export type TradeDateTimeFields = {
  entryDate: string
  exitDate: string
  entryTime: string
  exitTime: string
}

/**
 * Populate form fields from stored trade row.
 * Prefers entry_time / exit_time; falls back to trade_date only when timestamps absent.
 */
export function dateTimeFieldsFromTrade(t: {
  entry_time?: unknown
  exit_time?: unknown
  trade_date?: unknown
} | null | undefined): TradeDateTimeFields {
  const today = getESTDate()
  const entryFromTs = t?.entry_time ? toDateInputValue(t.entry_time) : ""
  const exitFromTs = t?.exit_time ? toDateInputValue(t.exit_time) : ""
  const entryTime = toTimeInputValue(t?.entry_time)
  const exitTime = toTimeInputValue(t?.exit_time)

  if (entryFromTs || exitFromTs) {
    return {
      entryDate: entryFromTs || exitFromTs || today,
      exitDate: exitFromTs || entryFromTs || today,
      entryTime,
      exitTime,
    }
  }

  const fallbackDate = t?.trade_date
    ? toDateInputValue(t.trade_date) || today
    : today

  return {
    entryDate: fallbackDate,
    exitDate: fallbackDate,
    entryTime,
    exitTime,
  }
}

/** Human-readable hold duration from two ISO datetimes. */
export function getTradeFormDuration(
  start: string | null,
  end: string | null
): string | null {
  return formatHoldDurationFromTimes(start, end)
}

export function isExitBeforeEntry(
  entryDate: string,
  entryTime: string,
  exitDate: string,
  exitTime: string
): boolean {
  const entryDt = buildDateTime(entryDate, entryTime)
  const exitDt = buildDateTime(exitDate, exitTime)
  if (!entryDt || !exitDt) return false
  return new Date(exitDt) <= new Date(entryDt)
}
