import { checkInDateKey, isCheckInDateKey } from "../dailyCheckIn/dateKey.ts"

export type PsychologyTradeDateFields = {
  entry_time?: string | null
  created_at?: string | null
  date?: string | null
}

/**
 * Eastern calendar `YYYY-MM-DD` for a trade — iOS
 * `TraderPsychologyAnalyticsFoundation.tradeDateKey` (`entryAt`).
 * Does not use the 18:00 ET futures rollover.
 */
export function psychologyTradeDateKey(
  trade: PsychologyTradeDateFields
): string {
  const entry = String(trade.entry_time ?? "").trim()
  if (entry) {
    if (isCheckInDateKey(entry)) return entry
    const fromEntry = dateKeyFromInstant(entry)
    if (fromEntry) return fromEntry
  }

  const created = String(trade.created_at ?? "").trim()
  if (created) {
    const fromCreated = dateKeyFromInstant(created)
    if (fromCreated) return fromCreated
  }

  const date = String(trade.date ?? "").trim()
  return isCheckInDateKey(date) ? date : ""
}

function dateKeyFromInstant(value: string): string {
  const instant = new Date(value)
  if (Number.isNaN(instant.getTime())) return ""
  return checkInDateKey(instant)
}
