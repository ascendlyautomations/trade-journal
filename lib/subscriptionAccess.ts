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
  creator_access?: boolean | null
  subscription_status?: string | null
  trial_end?: string | null
  early_access_enrolled_at?: string | null
  early_access_started_at?: string | null
  early_access_status?: string | null
  early_access_ends_at?: string | null
  early_access_campaign_id?: string | null
  early_access_enrollment_source?: string | null
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

/**
 * Users who may use the app without passing through signup checkout.
 * Pro/trial/beta stay exempt; completed onboarding grants Free access without
 * `use_free_tier` or promotional enrollment RPCs.
 */
export function isSubscriptionExempt(
  profile: SubscriptionAccessProfile | null | undefined
): boolean {
  if (!profile) return false
  if (profile.id && isDemoUserId(profile.id)) return true
  if (profile.is_beta_tester === true) return true
  if (isBetaReferralRef(profile.referred_by)) return true
  if (profile.use_free_tier === true) return true
  if (profile.onboarding_completed === true) return true
  return isProActive(profile)
}

/** True only when profile is complete but still blocked from the app (should not happen in normal web signup). */
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
  "/early-access",
  "/reset-password",
  "/creator",
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
): "/onboarding" | "/dashboard" {
  if (!profile || profileNeedsOnboarding(profile)) {
    return resolveSignupProfileSetupPath()
  }
  return "/dashboard"
}
