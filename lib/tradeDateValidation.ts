import { toDateInputValue } from "./inputTradeDateTime.ts"

/** Local calendar date as YYYY-MM-DD (HTML date input format). */
export function getLocalTodayDateInputValue(now = new Date()): string {
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, "0")
  const d = String(now.getDate()).padStart(2, "0")
  return `${y}-${m}-${d}`
}

/** True when `dateInput` is after today in the user's local timezone. */
export function isDateAfterToday(dateInput: string, now = new Date()): boolean {
  const trimmed = String(dateInput ?? "").trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return false
  return trimmed > getLocalTodayDateInputValue(now)
}

/** True when an ISO (or date) timestamp falls on a local calendar day after today. */
export function isIsoTimestampAfterToday(
  iso: string | null | undefined,
  now = new Date()
): boolean {
  if (iso == null || String(iso).trim() === "") return false
  const localDate = toDateInputValue(iso)
  if (!localDate) return false
  return isDateAfterToday(localDate, now)
}

export function tradeFormHasFutureDate(fields: {
  entryDate: string
  exitDate: string
}): boolean {
  return (
    isDateAfterToday(fields.entryDate) || isDateAfterToday(fields.exitDate)
  )
}

export function csvTradeHasFutureDate(trade: {
  date?: string | null
  entry_time?: string | null
  exit_time?: string | null
}): boolean {
  const dateField = trade.date ? toDateInputValue(trade.date) : ""
  if (dateField && isDateAfterToday(dateField)) return true
  if (isIsoTimestampAfterToday(trade.entry_time)) return true
  if (isIsoTimestampAfterToday(trade.exit_time)) return true
  return false
}

export function csvTradesHaveFutureDate(
  trades: Array<{
    date?: string | null
    entry_time?: string | null
    exit_time?: string | null
  }>
): boolean {
  return trades.some(csvTradeHasFutureDate)
}

/** True when a non-empty profile "started trading" date is after today (local). */
export function isStartedTradingDateInFuture(
  dateInput: string | null | undefined,
  now = new Date()
): boolean {
  const trimmed = String(dateInput ?? "").trim()
  if (!trimmed) return false
  return isDateAfterToday(trimmed, now)
}
