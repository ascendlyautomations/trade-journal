/**
 * Daily Check-In date keys — America/New_York calendar `YYYY-MM-DD`.
 * Matches iOS `TradingSessionLabel.easternTradeDateString` / `todayCheckInDateKey`.
 *
 * Do NOT use `getTradingDayKey` (18:00 ET futures rollover).
 */

const EASTERN_TIME_ZONE = "America/New_York"

const easternDateFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: EASTERN_TIME_ZONE,
  year: "numeric",
  month: "numeric",
  day: "numeric",
})

function pad2(value: number): string {
  return String(value).padStart(2, "0")
}

/** Eastern calendar date `YYYY-MM-DD` for an instant (defaults to now). */
export function checkInDateKey(now: Date = new Date()): string {
  const parts = easternDateFormatter.formatToParts(now)
  const year = Number(parts.find((part) => part.type === "year")?.value)
  const month = Number(parts.find((part) => part.type === "month")?.value)
  const day = Number(parts.find((part) => part.type === "day")?.value)
  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
    return ""
  }
  return `${year}-${pad2(month)}-${pad2(day)}`
}

/** Alias used by iOS `TraderDailyCheckInStore.todayDateKey`. */
export function todayCheckInDateKey(now: Date = new Date()): string {
  return checkInDateKey(now)
}

export function isCheckInDateKey(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value)
}

/** iOS `CheckInHistoryAggregator.defaultDayWindow`. */
export const CHECK_IN_HISTORY_DAY_WINDOW = 90

export function addCalendarDaysToDateKey(dateKey: string, delta: number): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey)
  if (!match) return ""
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const next = new Date(Date.UTC(year, month - 1, day + delta))
  return `${next.getUTCFullYear()}-${pad2(next.getUTCMonth() + 1)}-${pad2(next.getUTCDate())}`
}

/**
 * Inclusive start of the recent check-in window (Eastern calendar).
 * Web uses Eastern for both ends — unlike iOS history, which subtracts days
 * in the device calendar before converting to an Eastern key.
 */
export function checkInHistoryStartDateKey(
  dayLimit: number = CHECK_IN_HISTORY_DAY_WINDOW,
  now: Date = new Date()
): string {
  return addCalendarDaysToDateKey(todayCheckInDateKey(now), -(dayLimit - 1))
}
