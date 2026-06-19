import { formatEST, getESTDateKey } from "@/lib/formatDate"

const EST_TIMEZONE = "America/New_York"

function subtractOneDayFromDateKey(ymd: string): string {
  const [ys, ms, ds] = ymd.split("-").map(Number)
  if (!ys || !ms || !ds) return ""
  const d = new Date(Date.UTC(ys, ms - 1, ds))
  d.setUTCDate(d.getUTCDate() - 1)
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`
}

function parseTimestamp(dateString: string): number {
  const iso = dateString.includes("Z") ? dateString : `${dateString}Z`
  return new Date(iso).getTime()
}

/** Social-style comment timestamp: 2m, 1h, Yesterday, Jun 18. */
export function formatSocialCommentTime(
  dateString: string | null | undefined,
  now = new Date()
): string {
  if (!dateString) return ""

  const t = parseTimestamp(dateString)
  if (!Number.isFinite(t)) return ""

  const messageKey = getESTDateKey(dateString)
  if (!messageKey) return ""

  const todayKey = getESTDateKey(now.toISOString())
  const yesterdayKey = subtractOneDayFromDateKey(todayKey)
  const ageSec = Math.max(0, Math.floor((now.getTime() - t) / 1000))

  if (messageKey === todayKey) {
    if (ageSec < 60) return "now"
    if (ageSec < 3600) return `${Math.floor(ageSec / 60)}m`
    return `${Math.floor(ageSec / 3600)}h`
  }

  if (messageKey === yesterdayKey) return "Yesterday"

  const msgYear = Number(messageKey.split("-")[0])
  const nowYear = Number(todayKey.split("-")[0])
  const iso = dateString.includes("Z") ? dateString : `${dateString}Z`

  if (!Number.isFinite(msgYear) || msgYear < nowYear - 1) {
    return formatEST(iso)
  }

  return new Date(iso).toLocaleDateString("en-US", {
    timeZone: EST_TIMEZONE,
    month: "short",
    day: "numeric",
    ...(msgYear !== nowYear ? { year: "numeric" } : {}),
  })
}
