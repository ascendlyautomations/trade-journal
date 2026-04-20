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

