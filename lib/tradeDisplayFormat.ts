import { formatPnlCurrency } from "./formatMoney"
import { formatHoldDurationFromTimes, formatHoldDurationSeconds } from "./tradeTimingDisplay.ts"

/** Entry/exit price: always $X,XXX.XX (non-PnL semantics; still currency). */
export function formatTradePrice(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—"
  const n = Number(value)
  if (!Number.isFinite(n)) return "—"
  return formatPnlCurrency(n)
}

/**
 * Format stored entry_time / exit_time (ISO or time-only) for UI.
 * Prefers local clock time; strips redundant date when same calendar day as created_at if passed.
 */
export function formatTradeClockTime(
  value: unknown,
  opts?: { sameDayAs?: string | null }
): string {
  if (value === null || value === undefined || value === "") return "—"
  const raw = String(value).trim()
  if (!raw) return "—"

  const d = new Date(raw)
  if (!Number.isNaN(d.getTime())) {
    const same = opts?.sameDayAs
    if (same) {
      const b = new Date(same)
      if (
        !Number.isNaN(b.getTime()) &&
        d.getFullYear() === b.getFullYear() &&
        d.getMonth() === b.getMonth() &&
        d.getDate() === b.getDate()
      ) {
        return d.toLocaleTimeString(undefined, {
          hour: "numeric",
          minute: "2-digit",
          second: "2-digit",
        })
      }
    }
    return d.toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
      second: "2-digit",
    })
  }

  if (/^\d{1,2}:\d{2}/.test(raw)) return raw
  return raw
}

/** Format duration_seconds for cards (e.g. 2h 15m, 1d 2h). */
export function formatDurationSeconds(seconds: unknown): string {
  if (!shouldDisplayDuration(seconds)) return "—"
  return formatHoldDurationSeconds(Math.floor(Number(seconds))) ?? "—"
}

export function shouldDisplayDuration(seconds: unknown): boolean {
  if (seconds === null || seconds === undefined || seconds === "") return false
  const n = Math.floor(Number(seconds))
  return Number.isFinite(n) && n > 0
}

export function getTradeDurationDisplay(
  durationText: unknown,
  durationSeconds: unknown,
  entryTime?: string | null,
  exitTime?: string | null
): string | null {
  const rawText = durationText == null ? "" : String(durationText).trim()
  if (rawText) return rawText
  if (shouldDisplayDuration(durationSeconds)) {
    const formatted = formatDurationSeconds(durationSeconds)
    return formatted === "—" ? null : formatted
  }
  return formatHoldDurationFromTimes(entryTime, exitTime)
}
