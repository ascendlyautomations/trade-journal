import { isBetaReferralRef } from "./betaReferralCode"
import { isDemoUserId } from "./demo/constants"
import {
  profileNeedsOnboarding,
  type ProfileOnboardingGateFields,
} from "./profileOnboardingGate"
import { resolveSignupProfileSetupPath } from "./signupFlow"
import { shouldReconcileStripeMembership } from "./stripeReconciliation"
import { isProActive } from "./subscription"

export type SubscriptionAccessProfile = ProfileOnboardingGateFields & {
  id?: string | null
  is_pro?: boolean | null
  subscription_status?: string | null
  trial_end?: string | null
  is_beta_tester?: boolean | null
  referred_by?: string | null
  use_free_tier?: boolean | null
}

/** User has an active trial, paid plan, or beta access — not a marketing prospect. */
export function hasActiveMembership(
  profile: SubscriptionAccessProfile | null | undefined
): boolean {
  if (!profile) return false
  if (profileNeedsOnboarding(profile)) return false
  return isSubscriptionExempt(profile)
}

/** Beta, demo, paid, and trialing users skip Stripe checkout. */
export function isSubscriptionExempt(
  profile: SubscriptionAccessProfile | null | undefined
): boolean {
  if (!profile) return false
  if (profile.id && isDemoUserId(profile.id)) return true
  if (profile.is_beta_tester === true) return true
  if (isBetaReferralRef(profile.referred_by)) return true
  if (profile.use_free_tier === true) return true
  return isProActive(profile)
}

/** Profile complete but no active subscription/trial (standard new signups). */
export function needsSubscriptionCheckout(
  profile: SubscriptionAccessProfile | null | undefined
): boolean {
  if (!profile) return false
  if (profileNeedsOnboarding(profile)) return false
  return !isSubscriptionExempt(profile)
}

/**
 * Suppress finish-trial redirects while Stripe membership is reconciling.
 * Prevents dashboard → finish-trial bounce before webhook/profile sync completes.
 */
export function isSubscriptionGateSuspended(
  userId: string | null | undefined,
  options?: { membershipReconciling?: boolean }
): boolean {
  if (!userId || isDemoUserId(userId)) return false
  if (options?.membershipReconciling) return true
  return shouldReconcileStripeMembership(userId)
}

export const SUBSCRIPTION_GATE_EXACT_PATHS = ["/finish-trial"] as const

export const SUBSCRIPTION_GATE_PATH_PREFIXES = [
  "/login",
  "/onboarding",
  "/choose-plan",
  "/reset-password",
  "/privacy",
  "/terms",
  "/refund-policy",
  "/demo",
] as const

export function isAllowedPathWithoutSubscription(pathname: string): boolean {
  if (
    SUBSCRIPTION_GATE_EXACT_PATHS.includes(
      pathname as (typeof SUBSCRIPTION_GATE_EXACT_PATHS)[number]
    )
  ) {
    return true
  }
  return SUBSCRIPTION_GATE_PATH_PREFIXES.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`)
  )
}

/** Post-auth destination for standard app entry (not explicit checkout upgrade). */
export function resolvePostAuthAppPath(
  profile: SubscriptionAccessProfile | null | undefined
): "/choose-plan" | "/onboarding" | "/finish-trial" | "/dashboard" {
  if (!profile || profileNeedsOnboarding(profile)) return resolveSignupProfileSetupPath()
  if (needsSubscriptionCheckout(profile)) return "/finish-trial"
  return "/dashboard"
}
