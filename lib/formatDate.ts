const EST_TIMEZONE = "America/New_York"

export { formatEST } from "./formatEST"

function parseDateLike(value: string | Date | null | undefined): Date | null {
  if (!value) return null
  const d = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(d.getTime())) return null
  return d
}

export function formatESTDate(dateString: string | null | undefined): string {
  const d = parseDateLike(dateString)
  if (!d) return ""
  return d.toLocaleDateString("en-US", {
    timeZone: EST_TIMEZONE,
    month: "short",
    day: "numeric",
    year: "numeric",
  })
}

export function formatESTTime(dateString: string | null | undefined): string {
  const d = parseDateLike(dateString)
  if (!d) return ""
  return d.toLocaleTimeString("en-US", {
    timeZone: EST_TIMEZONE,
    hour: "numeric",
    minute: "2-digit",
  })
}

/** Time of day only (no date) in the runtime’s local zone — for entry/exit segments next to a full date line. */
export function formatTimeOnly(
  val: string | Date | null | undefined
): string | null {
  if (val == null || val === "") return null
  const d = val instanceof Date ? val : new Date(val)
  if (Number.isNaN(d.getTime())) return null
  return d.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  })
}

/** Date only (M/D/YY) in the runtime’s local zone — for trade card first segment. */
export function formatDateOnly(
  val: string | Date | null | undefined
): string {
  if (val == null || val === "") return ""
  const d = val instanceof Date ? val : new Date(val)
  if (Number.isNaN(d.getTime())) return ""
  return d.toLocaleDateString("en-US", {
    month: "numeric",
    day: "numeric",
    year: "2-digit",
  })
}

/** America/New_York calendar date key (YYYY-MM-DD). Matches app/calendar/page.tsx. */
export function getESTDateKey(value: string | Date | null | undefined): string {
  if (value == null || value === "") return ""

  const dateString =
    value instanceof Date ? value.toISOString() : String(value).trim()
  if (!dateString) return ""

  const iso = dateString.includes("Z") ? dateString : `${dateString}Z`
  const est = new Date(iso).toLocaleString("en-US", {
    timeZone: EST_TIMEZONE,
  })
  const d = new Date(est)
  if (Number.isNaN(d.getTime())) return ""

  const year = d.getFullYear()
  const month = d.getMonth() + 1
  const day = d.getDate()

  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`
}

/** Grid cell key for the visible local month (same shape as getESTDateKey). */
export function toDateKey(
  y: number,
  mZeroBased: number,
  dayNum: number
): string {
  return `${y}-${String(mZeroBased + 1).padStart(2, "0")}-${String(dayNum).padStart(2, "0")}`
}

function estWallClockParts(instant: Date): {
  y: number
  m: number
  d: number
  hour: number
} {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: EST_TIMEZONE,
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    hour12: false,
  }).formatToParts(instant)

  const get = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((p) => p.type === type)?.value ?? NaN)

  return {
    y: get("year"),
    m: get("month"),
    d: get("day"),
    hour: get("hour"),
  }
}

/** Add calendar days using UTC math (stable for Y-M-D stepping). */
function addCalendarDaysUTC(
  y: number,
  m: number,
  d: number,
  delta: number
): { y: number; m: number; d: number } {
  const utc = Date.UTC(y, m - 1, d + delta)
  const nd = new Date(utc)
  return {
    y: nd.getUTCFullYear(),
    m: nd.getUTCMonth() + 1,
    d: nd.getUTCDate(),
  }
}

/**
 * Futures-style trading calendar day (YYYY-MM-DD): America/New_York wall clock,
 * session rolls to the **next** calendar day at 18:00 local Eastern.
 */
export function getTradingDayKey(
  dateString: string | Date | null | undefined
): string | null {
  if (dateString == null || dateString === "") return null
  const instant =
    dateString instanceof Date ? dateString : new Date(String(dateString).trim())
  if (Number.isNaN(instant.getTime())) return null

  let { y, m, d, hour } = estWallClockParts(instant)

  if (hour >= 18) {
    const next = addCalendarDaysUTC(y, m, d, 1)
    y = next.y
    m = next.m
    d = next.d
  }

  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`
}

/**
 * Long weekday name for the futures trading session day (same 6PM rollover as {@link getTradingDayKey}).
 */
export function getTradingWeekday(
  dateString: string | Date | null | undefined
): string | null {
  const key = getTradingDayKey(dateString)
  if (!key) return null
  const [ys, ms, ds] = key.split("-").map(Number)
  const probe = new Date(Date.UTC(ys, ms - 1, ds, 16, 0, 0))
  return probe.toLocaleDateString("en-US", {
    weekday: "long",
    timeZone: EST_TIMEZONE,
  })
}

/**
 * Resolve entry/exit time to a string parseable by {@link getTradingDayKey}:
 * full ISO/datetime uses as-is; `HH:MM` pairs with `created_at` EST calendar date.
 */
export function resolveTradingTimeSourceForKey(trade: {
  created_at?: string | null
  date?: string | null
  entry_time?: string | null
  exit_time?: string | null
}): string | null {
  const timeRaw = trade.entry_time || trade.exit_time
  if (timeRaw == null || String(timeRaw).trim() === "") return null

  const tr = String(timeRaw).trim()
  const direct = new Date(tr)
  if (!Number.isNaN(direct.getTime())) return tr

  const base = trade.created_at ?? trade.date
  if (!base) return null

  const dayKey = getESTDateKey(String(base))
  if (!dayKey) return null

  const m = tr.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/)
  if (!m) return null

  const hh = m[1].padStart(2, "0")
  const mm = m[2].padStart(2, "0")
  const ss = (m[3] ?? "00").padStart(2, "0")
  return `${dayKey}T${hh}:${mm}:${ss}`
}

/**
 * Rough EST session bucket from a trade timestamp (entry/exit string).
 * Does not replace user-selected session on trades — for optional automation / debugging.
 */
export function getTradingSession(
  dateString: string | null | undefined
): string | null {
  if (!dateString) return null

  const date = new Date(dateString)

  const estDate = new Date(
    date.toLocaleString("en-US", { timeZone: EST_TIMEZONE })
  )

  const hour = estDate.getHours()

  if (hour >= 18 || hour < 2) {
    return "Asia"
  }

  if (hour >= 2 && hour < 9) {
    return "London"
  }

  if (hour >= 9 && hour < 16) {
    return "NY"
  }

  return null
}

