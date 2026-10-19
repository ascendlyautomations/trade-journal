/**
 * Owner-only daily lifestyle / mental-state check-in.
 * Contract matches iOS `TraderDailyCheckIn` / `trader_daily_check_ins`.
 * Stress storage: 1 = Calm … 5 = Very Stressed. Do not invert.
 */

export type TraderDailyCheckIn = {
  id: string
  ownerProfileId: string
  /** Eastern trade date (`YYYY-MM-DD`) — matches `trades.trade_date` semantics. */
  checkInDate: string
  sleepHours: number | null
  sleepQuality: number | null
  morningRating: number | null
  stressLevel: number | null
  energyLevel: number | null
  focusLevel: number | null
  notes: string | null
  createdAt: string
  updatedAt: string
}

export type TraderDailyCheckInDraft = {
  checkInDate: string
  sleepHours: number | null
  sleepQuality: number
  morningRating: number
  stressLevel: number
  energyLevel: number
  focusLevel: number
  notes: string
}

/** Stress rating scale — 1 is calmest, 5 is most stressed. */
export const TRADER_DAILY_CHECK_IN_STRESS_LABELS: Record<number, string> = {
  1: "Calm",
  2: "Slightly Stressed",
  3: "Moderate",
  4: "Stressed",
  5: "Very Stressed",
}

export function stressLabel(level: number): string {
  return TRADER_DAILY_CHECK_IN_STRESS_LABELS[level] ?? `${level}/5`
}

export function stressDisplayText(level: number | null | undefined): string {
  if (level == null) return "—"
  return `${stressLabel(level)} (${level}/5)`
}

export function isElevatedStress(level: number): boolean {
  return level >= 4
}

export function emptyCheckInDraft(checkInDate: string): TraderDailyCheckInDraft {
  return {
    checkInDate,
    sleepHours: null,
    sleepQuality: 3,
    morningRating: 3,
    stressLevel: 3,
    energyLevel: 3,
    focusLevel: 3,
    notes: "",
  }
}

export function draftFromCheckIn(
  checkIn: TraderDailyCheckIn
): TraderDailyCheckInDraft {
  return {
    checkInDate: checkIn.checkInDate,
    sleepHours: checkIn.sleepHours,
    sleepQuality: checkIn.sleepQuality ?? 3,
    morningRating: checkIn.morningRating ?? 3,
    stressLevel: checkIn.stressLevel ?? 3,
    energyLevel: checkIn.energyLevel ?? 3,
    focusLevel: checkIn.focusLevel ?? 3,
    notes: checkIn.notes ?? "",
  }
}
