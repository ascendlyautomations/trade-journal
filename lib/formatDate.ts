const EST_TIMEZONE = "America/New_York"

function parseDateLike(value: string | Date | null | undefined): Date | null {
  if (!value) return null
  const d = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(d.getTime())) return null
  return d
}

export function formatEST(dateString: string): string {
  const d = parseDateLike(dateString)
  if (!d) return ""
  return d.toLocaleString("en-US", {
    timeZone: EST_TIMEZONE,
    month: "numeric",
    day: "numeric",
    year: "2-digit",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  })
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

export function getESTDateKey(value: string | Date | null | undefined): string {
  const d = parseDateLike(value)
  if (!d) return ""
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: EST_TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(d)
  const year = parts.find((p) => p.type === "year")?.value
  const month = parts.find((p) => p.type === "month")?.value
  const day = parts.find((p) => p.type === "day")?.value
  return year && month && day ? `${year}-${month}-${day}` : ""
}

