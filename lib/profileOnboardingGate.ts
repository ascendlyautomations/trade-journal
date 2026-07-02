/** Shared onboarding gate — single source of truth for global app access. */

export function profileNeedsUsername(
  username: string | null | undefined
): boolean {
  return username == null || String(username).trim() === ""
}

function profileFieldMissing(value: string | null | undefined): boolean {
  return value == null || String(value).trim() === ""
}

export type ProfileOnboardingGateFields = {
  username?: string | null
  onboarding_completed?: boolean | null
  trader_type?: string | null
  trading_style?: string | null
  started_trading?: string | null
}

/**
 * True when the user must complete global onboarding before app access.
 *
 * Existing users with `onboarding_completed === true` are never gated again,
 * even if optional profile fields are empty.
 */
export function profileNeedsOnboarding(
  profile: ProfileOnboardingGateFields
): boolean {
  if (profile.onboarding_completed === true) return false

  return (
    profileNeedsUsername(profile.username) ||
    profileFieldMissing(profile.trader_type) ||
    profileFieldMissing(profile.trading_style) ||
    profileFieldMissing(profile.started_trading) ||
    profile.onboarding_completed !== true
  )
}

/** Routes reachable while onboarding is still required. */
export const ONBOARDING_ALLOWED_PATH_PREFIXES = [
  "/onboarding",
  "/login",
  "/reset-password",
  "/privacy",
  "/terms",
  "/demo",
] as const

export function isAllowedPathDuringOnboarding(pathname: string): boolean {
  return ONBOARDING_ALLOWED_PATH_PREFIXES.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`)
  )
}
