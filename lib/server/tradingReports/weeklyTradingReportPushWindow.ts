const EASTERN = "America/New_York"

const easternWallClockFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: EASTERN,
  weekday: "short",
  hour: "numeric",
  minute: "numeric",
  hourCycle: "h23",
})

/**
 * Saturday 17:00 UTC, plus the 18:00 UTC retry.
 * Eastern: 12:00 EST / 13:00 EDT, and 13:00 EST / 14:00 EDT.
 * Window 12:00–14:59 ET Saturday.
 */
export function isWeeklyTradingReportPushWindow(now = new Date()): boolean {
  const parts = easternWallClockFormatter.formatToParts(now)
  const weekday = parts.find((p) => p.type === "weekday")?.value ?? ""
  if (weekday !== "Sat") return false
  const hour = Number.parseInt(
    parts.find((p) => p.type === "hour")?.value ?? "",
    10
  )
  const minute = Number.parseInt(
    parts.find((p) => p.type === "minute")?.value ?? "",
    10
  )
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return false
  const minutesSinceMidnight = hour * 60 + minute
  const windowStart = 12 * 60
  const windowEnd = 14 * 60 + 59
  return minutesSinceMidnight >= windowStart && minutesSinceMidnight <= windowEnd
}
