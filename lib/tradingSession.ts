/** Eastern futures session labels stored on `trades.session` (web, iOS, Supabase). */
export const TRADING_SESSION_LABELS = {
  nyAM: "NY AM",
  nyLunch: "NY Lunch",
  nyPM: "NY PM",
  london: "London",
  asia: "Asia",
  after: "After",
} as const

export type TradingSessionLabel =
  (typeof TRADING_SESSION_LABELS)[keyof typeof TRADING_SESSION_LABELS]

export const TRADING_SESSION_DISPLAY_ORDER: readonly TradingSessionLabel[] = [
  TRADING_SESSION_LABELS.nyAM,
  TRADING_SESSION_LABELS.nyLunch,
  TRADING_SESSION_LABELS.nyPM,
  TRADING_SESSION_LABELS.london,
  TRADING_SESSION_LABELS.asia,
  TRADING_SESSION_LABELS.after,
] as const

export const DEFAULT_TRADING_SESSION: TradingSessionLabel =
  TRADING_SESSION_LABELS.nyAM

const EASTERN_TZ = "America/New_York"

/** Wall-clock minutes since midnight in US Eastern (DST-aware via IANA zone). */
export function easternMinutesSinceMidnight(date: Date): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: EASTERN_TZ,
    hour: "numeric",
    minute: "numeric",
    hour12: false,
  }).formatToParts(date)
  const hour = Number(parts.find((p) => p.type === "hour")?.value ?? "0")
  const minute = Number(parts.find((p) => p.type === "minute")?.value ?? "0")
  return hour * 60 + minute
}

function hoursToMinutes(h: number, m = 0): number {
  return h * 60 + m
}

/**
 * Session from entry timestamp — same boundaries as iOS `TradingSessionLabel` + Supabase `trading_session_from_et`.
 *
 * Asia: 6:00 PM – 1:59 AM
 * London: 2:00 AM – 7:59 AM
 * NY AM: 8:00 AM – 11:29 AM
 * NY Lunch: 11:30 AM – 1:29 PM
 * NY PM: 1:30 PM – 4:59 PM
 * After: 5:00 PM – 5:59 PM
 */
export function getSessionFromDate(
  dateInput: string | Date | null | undefined
): TradingSessionLabel | null {
  if (dateInput == null || dateInput === "") return null
  const d = dateInput instanceof Date ? dateInput : new Date(dateInput)
  if (Number.isNaN(d.getTime())) return null

  const t = easternMinutesSinceMidnight(d)

  if (t >= hoursToMinutes(18) || t < hoursToMinutes(2)) {
    return TRADING_SESSION_LABELS.asia
  }
  if (t >= hoursToMinutes(2) && t < hoursToMinutes(8)) {
    return TRADING_SESSION_LABELS.london
  }
  if (t >= hoursToMinutes(8) && t < hoursToMinutes(11, 30)) {
    return TRADING_SESSION_LABELS.nyAM
  }
  if (t >= hoursToMinutes(11, 30) && t < hoursToMinutes(13, 30)) {
    return TRADING_SESSION_LABELS.nyLunch
  }
  if (t >= hoursToMinutes(13, 30) && t < hoursToMinutes(17)) {
    return TRADING_SESSION_LABELS.nyPM
  }
  if (t >= hoursToMinutes(17) && t < hoursToMinutes(18)) {
    return TRADING_SESSION_LABELS.after
  }
  return null
}

/** Normalize stored / legacy session text to a canonical label for analytics. */
export function normalizeTradingSessionLabel(
  sessionRaw: string | null | undefined
): TradingSessionLabel | null {
  const v = (sessionRaw ?? "").trim().toLowerCase()
  if (!v) return null

  if (v === "ny am" || v === "new york am") return TRADING_SESSION_LABELS.nyAM
  if (v === "ny lunch" || v === "new york lunch" || v === "lunch") {
    return TRADING_SESSION_LABELS.nyLunch
  }
  if (v === "ny pm" || v === "new york pm" || v === "pm") {
    return TRADING_SESSION_LABELS.nyPM
  }
  if (v === "london" || v === "ldn" || v === "uk") {
    return TRADING_SESSION_LABELS.london
  }
  if (v === "asia" || v === "asian" || v === "tokyo") {
    return TRADING_SESSION_LABELS.asia
  }
  if (v === "after") return TRADING_SESSION_LABELS.after

  if (v.includes("lunch") && (v.includes("ny") || v.includes("new york"))) {
    return TRADING_SESSION_LABELS.nyLunch
  }
  if ((v.includes("pm") || v.includes("p.m")) && (v.includes("ny") || v.includes("new york"))) {
    return TRADING_SESSION_LABELS.nyPM
  }
  if ((v.includes("am") || v.includes("a.m")) && (v.includes("ny") || v.includes("new york"))) {
    return TRADING_SESSION_LABELS.nyAM
  }
  if (v === "ny" || v === "new york" || (v.includes("ny") && !v.includes("london"))) {
    return TRADING_SESSION_LABELS.nyAM
  }

  return null
}

export function tradingSessionDisplayName(
  label: TradingSessionLabel | string
): string {
  switch (label) {
    case TRADING_SESSION_LABELS.nyAM:
      return "New York AM"
    case TRADING_SESSION_LABELS.nyLunch:
      return "New York Lunch"
    case TRADING_SESSION_LABELS.nyPM:
      return "New York PM"
    case TRADING_SESSION_LABELS.london:
      return "London"
    case TRADING_SESSION_LABELS.asia:
      return "Asia"
    case TRADING_SESSION_LABELS.after:
      return "After"
    default:
      return label
  }
}

export function tradingSessionFilterValue(label: TradingSessionLabel): string {
  return label.toLowerCase()
}
