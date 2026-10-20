export function formatEST(dateString: string) {
  if (!dateString) return ""

  const isoString = dateString.includes("Z")
    ? dateString
    : dateString + "Z"

  return new Date(isoString).toLocaleString("en-US", {
    timeZone: "America/New_York",
    month: "numeric",
    day: "numeric",
    year: "2-digit",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  })
}

/** Equity curve tooltips — parse ISO instants; avoid Invalid Date on partial times. */
export function formatDashboardChartTooltipLabel(label: unknown): string {
  const raw = String(label ?? "").trim()
  if (!raw) return ""

  const d = new Date(raw)
  if (!Number.isNaN(d.getTime())) {
    return d.toLocaleString("en-US", {
      timeZone: "America/New_York",
      month: "numeric",
      day: "numeric",
      year: "2-digit",
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    })
  }

  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    const dayOnly = new Date(`${raw}T12:00:00`)
    if (!Number.isNaN(dayOnly.getTime())) {
      return dayOnly.toLocaleDateString("en-US", {
        timeZone: "America/New_York",
        month: "numeric",
        day: "numeric",
        year: "2-digit",
      })
    }
  }

  return raw.length > 24 ? raw.slice(0, 24) : raw
}
