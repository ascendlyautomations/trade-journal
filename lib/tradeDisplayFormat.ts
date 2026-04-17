import { formatPnlCurrency } from "./formatMoney"

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

/** Format duration_seconds for cards (e.g. 1h 2m, 4m 34s). */
export function formatDurationSeconds(seconds: unknown): string {
  if (!shouldDisplayDuration(seconds)) return "—"
  const n = Math.floor(Number(seconds))
  const h = Math.floor(n / 3600)
  const m = Math.floor((n % 3600) / 60)
  const s = n % 60

  if (h > 0) {
    return `${h}h ${String(m).padStart(2, "0")}m`
  }
  if (m > 0) {
    return `${m}m ${s}s`
  }
  return `${s}s`
}

export function shouldDisplayDuration(seconds: unknown): boolean {
  if (seconds === null || seconds === undefined || seconds === "") return false
  const n = Math.floor(Number(seconds))
  return Number.isFinite(n) && n > 0
}

export function getTradeDurationDisplay(
  durationText: unknown,
  durationSeconds: unknown
): string | null {
  const rawText = durationText == null ? "" : String(durationText).trim()
  if (rawText) return rawText
  if (!shouldDisplayDuration(durationSeconds)) return null
  const formatted = formatDurationSeconds(durationSeconds)
  return formatted === "—" ? null : formatted
}
