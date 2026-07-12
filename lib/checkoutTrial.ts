/**
 * Central source of truth for Stripe Checkout free-trial configuration.
 * Production path: 14-day trial for eligible first-time subscribers.
 */

export const CHECKOUT_TRIAL_ENABLED = true

const DEFAULT_TRIAL_DAYS = 14

function readConfiguredTrialDays(): number {
  const raw = Number(process.env.STRIPE_TRIAL_DAYS ?? DEFAULT_TRIAL_DAYS)
  if (Number.isNaN(raw) || raw < 0) return DEFAULT_TRIAL_DAYS
  return raw
}

/** Configured trial length in days (env `STRIPE_TRIAL_DAYS`, default 14). */
export const CHECKOUT_TRIAL_PERIOD_DAYS = readConfiguredTrialDays()

export type CheckoutTrialProfileHint = {
  trial_end?: string | null
}

/** True when this profile already consumed a TradeTraxs trial. */
export function profileHasUsedCheckoutTrial(
  profile: CheckoutTrialProfileHint | null | undefined
): boolean {
  const raw = profile?.trial_end
  if (raw == null) return false
  return String(raw).trim() !== ""
}

/**
 * Days to pass as `subscription_data.trial_period_days`, or `null` to omit.
 * Eligible = trial enabled and profile has never stored a trial_end.
 */
export function resolveCheckoutTrialPeriodDays(
  profile: CheckoutTrialProfileHint | null | undefined
): number | null {
  if (!CHECKOUT_TRIAL_ENABLED) return null
  if (profileHasUsedCheckoutTrial(profile)) return null
  if (CHECKOUT_TRIAL_PERIOD_DAYS <= 0) return null
  return CHECKOUT_TRIAL_PERIOD_DAYS
}
