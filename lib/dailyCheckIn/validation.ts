import type {
  TraderDailyCheckIn,
  TraderDailyCheckInDraft,
} from "./types.ts"

/** Port of iOS `TraderDailyCheckInValidation`. */
export const CHECK_IN_RATING_MIN = 1
export const CHECK_IN_RATING_MAX = 5
export const CHECK_IN_SLEEP_HOURS_MIN = 0
export const CHECK_IN_SLEEP_HOURS_MAX = 24

export function isRatingInRange(value: number | null | undefined): boolean {
  return (
    value != null &&
    Number.isInteger(value) &&
    value >= CHECK_IN_RATING_MIN &&
    value <= CHECK_IN_RATING_MAX
  )
}

export function isSleepHoursInRange(value: number | null | undefined): boolean {
  return (
    value != null &&
    Number.isFinite(value) &&
    value >= CHECK_IN_SLEEP_HOURS_MIN &&
    value <= CHECK_IN_SLEEP_HOURS_MAX
  )
}

export function isCompleteCheckIn(checkIn: TraderDailyCheckIn): boolean {
  if (!isSleepHoursInRange(checkIn.sleepHours)) return false
  return [
    checkIn.sleepQuality,
    checkIn.morningRating,
    checkIn.stressLevel,
    checkIn.energyLevel,
    checkIn.focusLevel,
  ].every((rating) => isRatingInRange(rating))
}

export function validateCheckInDraft(
  draft: TraderDailyCheckInDraft
): string | null {
  if (!isSleepHoursInRange(draft.sleepHours)) {
    return "Enter hours of sleep between 0 and 24."
  }
  const ratings: Array<[string, number]> = [
    ["Sleep quality", draft.sleepQuality],
    ["Morning rating", draft.morningRating],
    ["Stress", draft.stressLevel],
    ["Energy", draft.energyLevel],
    ["Focus", draft.focusLevel],
  ]
  for (const [label, value] of ratings) {
    if (!isRatingInRange(value)) {
      return `${label} must be between 1 and 5.`
    }
  }
  return null
}

/** Unsigned decimal, max 1 fraction digit — iOS `NumericInputStyle.unsignedDecimal`. */
export function parseSleepHoursInput(raw: string): number | null {
  const trimmed = raw.trim()
  if (!trimmed) return null
  if (!/^\d+(\.\d{1})?$/.test(trimmed) && !/^\d+\.$/.test(trimmed)) {
    return null
  }
  const parsed = Number(trimmed)
  if (!Number.isFinite(parsed)) return null
  return parsed
}

export function formatSleepHoursInput(hours: number | null): string {
  if (hours == null || !Number.isFinite(hours)) return ""
  const rounded = Math.round(hours * 10) / 10
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1)
}

export function sanitizeSleepHoursTyping(raw: string): string {
  const stripped = raw.replace(/[^\d.]/g, "")
  const dot = stripped.indexOf(".")
  if (dot === -1) return stripped.slice(0, 4)
  const whole = stripped.slice(0, dot).slice(0, 2)
  const fraction = stripped.slice(dot + 1).replace(/\./g, "").slice(0, 1)
  return `${whole}.${fraction}`
}
