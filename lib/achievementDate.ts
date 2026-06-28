import { toDateInputValue } from "./inputTradeDateTime.ts"
import { getLocalTodayDateInputValue } from "./tradeDateValidation.ts"

/** Default achieved date for a new achievement upload (local YYYY-MM-DD). */
export function getDefaultAchievementDateInputValue(now = new Date()): string {
  return getLocalTodayDateInputValue(now)
}

/**
 * Normalize stored/form dates to local YYYY-MM-DD without UTC day shift.
 * Date-only strings must stay calendar-stable across timezones.
 */
export function normalizeAchievementDateInputValue(
  value: string | null | undefined
): string {
  if (value == null || String(value).trim() === "") return ""
  const trimmed = String(value).trim()
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed
  return toDateInputValue(value)
}

/** Resolve the initial achieved date for a new upload (explicit override or today). */
export function resolveNewAchievementDateInputValue(
  initialValues?: { achieved_at?: string | null }
): string {
  const fromInitial = normalizeAchievementDateInputValue(initialValues?.achieved_at)
  return fromInitial || getDefaultAchievementDateInputValue()
}
