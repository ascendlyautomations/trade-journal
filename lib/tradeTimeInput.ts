/**
 * Trade form time values: stored as HH:mm (24h) for buildDateTime / DB.
 * Display uses 12-hour clock with AM/PM (matches TradeTraxs clock formatting).
 */

export type TimePeriod = "AM" | "PM"

export type TimeParts = {
  hour12: number
  minute: number
  period: TimePeriod
}

const HHMM_RE = /^([01]?\d|2[0-3]):([0-5]\d)$/

/** Normalize any accepted time string to HH:mm, or "" if empty/invalid. */
export function normalizeTradeTimeValue(raw: unknown): string {
  const parsed = parseTypedTradeTime(String(raw ?? ""))
  return parsed ?? ""
}

export function isValidHhmm(value: string): boolean {
  return HHMM_RE.test(String(value ?? "").trim())
}

export function hhmmToParts(hhmm: string): TimeParts | null {
  const normalized = String(hhmm ?? "").trim()
  if (!HHMM_RE.test(normalized)) return null
  const [hStr, mStr] = normalized.split(":")
  const hour24 = Number(hStr)
  const minute = Number(mStr)
  if (!Number.isFinite(hour24) || !Number.isFinite(minute)) return null
  const period: TimePeriod = hour24 >= 12 ? "PM" : "AM"
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12
  return { hour12, minute, period }
}

export function partsToHhmm(
  hour12: number,
  minute: number,
  period: TimePeriod
): string {
  const h = Math.min(12, Math.max(1, Math.round(hour12)))
  const m = Math.min(59, Math.max(0, Math.round(minute)))
  let hour24 = h % 12
  if (period === "PM") hour24 += 12
  return `${String(hour24).padStart(2, "0")}:${String(m).padStart(2, "0")}`
}

/** Display string for the text field, e.g. "9:30 AM". */
export function formatHhmmForDisplay(hhmm: string): string {
  const parts = hhmmToParts(hhmm)
  if (!parts) return ""
  return `${parts.hour12}:${String(parts.minute).padStart(2, "0")} ${parts.period}`
}

/**
 * Parse user-typed time into HH:mm.
 * Accepts: "9:30 AM", "09:30", "9:30am", "21:05", "930am", etc.
 */
export function parseTypedTradeTime(raw: string): string | null {
  const s = String(raw ?? "").trim()
  if (!s) return ""

  const cleaned = s.replace(/\s+/g, " ").trim()

  // 12h with AM/PM
  const ampm = cleaned.match(
    /^(\d{1,2})(?::(\d{1,2}))?\s*(a\.?m\.?|p\.?m\.?)$/i
  )
  if (ampm) {
    const hour12 = Number(ampm[1])
    const minute = ampm[2] != null ? Number(ampm[2]) : 0
    if (hour12 < 1 || hour12 > 12 || minute < 0 || minute > 59) return null
    const period: TimePeriod = /^p/i.test(ampm[3]) ? "PM" : "AM"
    return partsToHhmm(hour12, minute, period)
  }

  // Compact 12h: 930am / 1230pm
  const compactAmpm = cleaned.match(/^(\d{3,4})\s*(a\.?m\.?|p\.?m\.?)$/i)
  if (compactAmpm) {
    const digits = compactAmpm[1]
    const minute = Number(digits.slice(-2))
    const hour12 = Number(digits.slice(0, -2))
    if (hour12 < 1 || hour12 > 12 || minute < 0 || minute > 59) return null
    const period: TimePeriod = /^p/i.test(compactAmpm[2]) ? "PM" : "AM"
    return partsToHhmm(hour12, minute, period)
  }

  // 24h HH:mm or H:mm (optional seconds)
  const twentyFour = cleaned.match(/^([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$/)
  if (twentyFour) {
    return `${String(Number(twentyFour[1])).padStart(2, "0")}:${twentyFour[2]}`
  }

  // Compact 24h: 930 → 09:30, 2130 → 21:30
  const compact24 = cleaned.match(/^(\d{3,4})$/)
  if (compact24) {
    const digits = compact24[1]
    const minute = Number(digits.slice(-2))
    const hour24 = Number(digits.slice(0, -2))
    if (hour24 < 0 || hour24 > 23 || minute < 0 || minute > 59) return null
    return `${String(hour24).padStart(2, "0")}:${String(minute).padStart(2, "0")}`
  }

  return null
}

export const HOUR12_OPTIONS = Array.from({ length: 12 }, (_, i) => i + 1)
export const MINUTE_OPTIONS = Array.from({ length: 60 }, (_, i) => i)
export const PERIOD_OPTIONS: TimePeriod[] = ["AM", "PM"]
