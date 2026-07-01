import {
  formatESTTime,
  getESTDateKey,
  parseDateLike,
} from "./formatDate.ts"

const EST_TIMEZONE = "America/New_York"
const SECOND_MS = 1000
const MINUTE_MS = 60 * SECOND_MS
const HOUR_MS = 60 * MINUTE_MS
const DAY_MS = 24 * HOUR_MS

export type RelativeTimeStyle = "long" | "compact"

export type NotificationTimeSection =
  | "today"
  | "yesterday"
  | "earlier_this_week"
  | "last_week"
  | "earlier_this_month"
  | "older"

export const NOTIFICATION_TIME_SECTION_ORDER: NotificationTimeSection[] = [
  "today",
  "yesterday",
  "earlier_this_week",
  "last_week",
  "earlier_this_month",
  "older",
]

export const NOTIFICATION_TIME_SECTION_LABELS: Record<
  NotificationTimeSection,
  string
> = {
  today: "Today",
  yesterday: "Yesterday",
  earlier_this_week: "Earlier This Week",
  last_week: "Last Week",
  earlier_this_month: "Earlier This Month",
  older: "Older",
}

function subtractOneDayFromDateKey(ymd: string): string {
  const [ys, ms, ds] = ymd.split("-").map(Number)
  if (!ys || !ms || !ds) return ""
  const d = new Date(Date.UTC(ys, ms - 1, ds))
  d.setUTCDate(d.getUTCDate() - 1)
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`
}

function mondayOfWeekDateKey(dateKey: string): string {
  const [ys, ms, ds] = dateKey.split("-").map(Number)
  if (!ys || !ms || !ds) return dateKey
  const d = new Date(Date.UTC(ys, ms - 1, ds))
  const dow = d.getUTCDay()
  const mondayOffset = dow === 0 ? 6 : dow - 1
  d.setUTCDate(d.getUTCDate() - mondayOffset)
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`
}

function subtractDaysFromDateKey(ymd: string, days: number): string {
  const [ys, ms, ds] = ymd.split("-").map(Number)
  if (!ys || !ms || !ds) return ymd
  const d = new Date(Date.UTC(ys, ms - 1, ds))
  d.setUTCDate(d.getUTCDate() - days)
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`
}

function pluralize(count: number, singular: string, plural = `${singular}s`): string {
  return count === 1 ? singular : plural
}

function formatShortEstDate(iso: string): string {
  const d = parseDateLike(iso)
  if (!d) return ""
  return d.toLocaleDateString("en-US", {
    timeZone: EST_TIMEZONE,
    month: "short",
    day: "numeric",
    year: "numeric",
  })
}

/**
 * Relative timestamp for social surfaces (notifications, feed, comments, rooms).
 * Long style: "Just now", "5 minutes ago", "3 weeks ago".
 * Compact style: "now", "5m", "3w" (comments / stories).
 */
export function formatRelativeTime(
  dateString: string | Date | null | undefined,
  now: Date | number = Date.now(),
  style: RelativeTimeStyle = "long"
): string {
  const d = parseDateLike(dateString)
  if (!d) return ""

  const nowMs = typeof now === "number" ? now : now.getTime()
  const t = d.getTime()
  if (!Number.isFinite(t) || !Number.isFinite(nowMs)) return ""

  const diffMs = Math.max(0, nowMs - t)
  const diffSec = Math.floor(diffMs / SECOND_MS)

  if (diffSec < 30) {
    return "Just now"
  }

  if (diffSec < 60) {
    return style === "compact"
      ? `${diffSec}s`
      : `${diffSec} ${pluralize(diffSec, "second")} ago`
  }

  const diffMin = Math.floor(diffMs / MINUTE_MS)
  if (diffMin < 60) {
    return style === "compact"
      ? `${diffMin}m`
      : `${diffMin} ${pluralize(diffMin, "minute")} ago`
  }

  const diffHours = Math.floor(diffMs / HOUR_MS)
  if (diffHours < 24) {
    return style === "compact"
      ? `${diffHours}h`
      : `${diffHours} ${pluralize(diffHours, "hour")} ago`
  }

  const diffDays = Math.floor(diffMs / DAY_MS)
  if (diffDays < 2) {
    return "Yesterday"
  }

  if (diffDays <= 6) {
    return style === "compact"
      ? `${diffDays}d`
      : `${diffDays} ${pluralize(diffDays, "day")} ago`
  }

  const diffWeeks = Math.floor(diffDays / 7)
  if (diffWeeks <= 4) {
    return style === "compact"
      ? `${diffWeeks}w`
      : `${diffWeeks} ${pluralize(diffWeeks, "week")} ago`
  }

  const months = Math.max(
    1,
    (new Date(nowMs).getFullYear() - d.getFullYear()) * 12 +
      (new Date(nowMs).getMonth() - d.getMonth())
  )
  if (months < 12) {
    return style === "compact"
      ? `${months}mo`
      : `${months} ${pluralize(months, "month")} ago`
  }

  const years = Math.max(1, Math.floor(months / 12))
  return style === "compact"
    ? `${years}y`
    : `${years} ${pluralize(years, "year")} ago`
}

/**
 * Canonical compact relative timestamp for notifications, feed, comments, and replies.
 * Just now → 45s → 1m → 1h → Yesterday → 2d → 1w → 2mo → 1y
 */
export function formatSocialTimestamp(
  dateString: string | Date | null | undefined,
  now: Date | number = Date.now()
): string {
  return formatRelativeTime(dateString, now, "compact")
}

/**
 * Posted/published timestamp for public trade cards.
 * Just now → 5m ago → 2h ago → Yesterday → 3d ago → Jun 18 → Jun 18, 2025
 */
export function formatPostedTimestamp(
  dateString: string | Date | null | undefined,
  now: Date | number = Date.now()
): string {
  const d = parseDateLike(dateString)
  if (!d) return ""

  const nowMs = typeof now === "number" ? now : now.getTime()
  const t = d.getTime()
  if (!Number.isFinite(t) || !Number.isFinite(nowMs)) return ""

  const iso =
    typeof dateString === "string" ? dateString : dateString.toISOString()
  const diffMs = Math.max(0, nowMs - t)
  const diffSec = Math.floor(diffMs / SECOND_MS)

  if (diffSec < 30) return "Just now"

  const diffMin = Math.floor(diffMs / MINUTE_MS)
  if (diffMin < 60) {
    return `${Math.max(1, diffMin)}m ago`
  }

  const diffHours = Math.floor(diffMs / HOUR_MS)
  if (diffHours < 24) {
    return `${diffHours}h ago`
  }

  const diffDays = Math.floor(diffMs / DAY_MS)
  if (diffDays < 2) return "Yesterday"

  if (diffDays <= 6) {
    return `${diffDays}d ago`
  }

  const messageKey = getESTDateKey(iso)
  const todayKey = getESTDateKey(new Date(nowMs).toISOString())
  if (!messageKey || !todayKey) {
    return d.toLocaleDateString("en-US", {
      timeZone: EST_TIMEZONE,
      month: "short",
      day: "numeric",
      year: "numeric",
    })
  }

  const [ty] = todayKey.split("-")
  const [my] = messageKey.split("-")
  return d.toLocaleDateString("en-US", {
    timeZone: EST_TIMEZONE,
    month: "short",
    day: "numeric",
    ...(ty !== my ? { year: "numeric" } : {}),
  })
}

/** Calendar-based buckets for the notifications center (America/New_York). */
export function getNotificationTimeSection(
  iso: string,
  now: Date | number = Date.now()
): NotificationTimeSection {
  const messageKey = getESTDateKey(iso)
  if (!messageKey) return "older"

  const nowIso =
    typeof now === "number" ? new Date(now).toISOString() : now.toISOString()
  const todayKey = getESTDateKey(nowIso)
  if (!todayKey) return "older"

  if (messageKey === todayKey) return "today"

  const yesterdayKey = subtractOneDayFromDateKey(todayKey)
  if (messageKey === yesterdayKey) return "yesterday"

  const todayMonday = mondayOfWeekDateKey(todayKey)
  const messageMonday = mondayOfWeekDateKey(messageKey)

  if (messageMonday === todayMonday) return "earlier_this_week"

  const lastWeekMonday = subtractDaysFromDateKey(todayMonday, 7)
  if (messageMonday === lastWeekMonday) return "last_week"

  const [ty, tm] = todayKey.split("-")
  const [my, mm] = messageKey.split("-")
  if (ty === my && tm === mm) return "earlier_this_month"

  return "older"
}

/**
 * Inbox / conversation list timestamps (America/New_York calendar).
 * Just now → 2m → 4:32 PM (today) → Yesterday → Mon → Jun 24.
 */
export function formatConversationListTime(
  dateString: string | Date | null | undefined,
  now: Date | number = Date.now()
): string {
  if (!dateString) return ""

  const d = parseDateLike(dateString)
  if (!d) return ""

  const nowMs = typeof now === "number" ? now : now.getTime()
  const iso =
    typeof dateString === "string" ? dateString : dateString.toISOString()
  const diffMs = Math.max(0, nowMs - d.getTime())
  const diffSec = Math.floor(diffMs / SECOND_MS)

  if (diffSec < 30) return "Just now"

  const diffMin = Math.floor(diffMs / MINUTE_MS)
  if (diffMin < 60) return `${diffMin}m`

  const messageKey = getESTDateKey(iso)
  const todayKey = getESTDateKey(new Date(nowMs).toISOString())
  if (!messageKey || !todayKey) {
    return formatRelativeTime(dateString, now, "compact")
  }

  if (messageKey === todayKey) {
    return formatESTTime(iso)
  }

  const yesterdayKey = subtractOneDayFromDateKey(todayKey)
  if (messageKey === yesterdayKey) return "Yesterday"

  const todayMonday = mondayOfWeekDateKey(todayKey)
  const messageMonday = mondayOfWeekDateKey(messageKey)
  const lastWeekMonday = subtractDaysFromDateKey(todayMonday, 7)

  if (messageMonday === todayMonday || messageMonday === lastWeekMonday) {
    return d.toLocaleDateString("en-US", {
      timeZone: EST_TIMEZONE,
      weekday: "short",
    })
  }

  const [ty] = todayKey.split("-")
  const [my] = messageKey.split("-")
  return d.toLocaleDateString("en-US", {
    timeZone: EST_TIMEZONE,
    month: "short",
    day: "numeric",
    ...(ty !== my ? { year: "numeric" } : {}),
  })
}

/** Fallback absolute label for very old notification rows in compact lists. */
export function formatRelativeTimeOrDate(
  dateString: string | Date | null | undefined,
  now: Date | number = Date.now(),
  style: RelativeTimeStyle = "long"
): string {
  const section = getNotificationTimeSection(
    typeof dateString === "string"
      ? dateString
      : dateString instanceof Date
        ? dateString.toISOString()
        : "",
    now
  )
  if (section === "older") {
    const iso =
      typeof dateString === "string"
        ? dateString
        : dateString instanceof Date
          ? dateString.toISOString()
          : ""
    return formatShortEstDate(iso) || formatRelativeTime(dateString, now, style)
  }
  return formatRelativeTime(dateString, now, style)
}
