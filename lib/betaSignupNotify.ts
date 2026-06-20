import { notifyAdminBetaSignup } from "@/lib/notifyAdminBetaSignup"
import { BETA_REFERRAL_CODE } from "@/lib/betaReferralCode"

function normalizeReferralCode(value: string | null | undefined): string {
  return value != null ? String(value).trim().toUpperCase() : ""
}

export function isProfileBetaSignupEligible(
  profile:
    | {
        is_beta_tester?: boolean | null
        referred_by?: string | null
      }
    | null
    | undefined
): boolean {
  if (!profile) return false
  if (profile.is_beta_tester === true) return true
  return normalizeReferralCode(profile.referred_by) === BETA_REFERRAL_CODE
}

/**
 * Fire admin beta signup email after onboarding profile save (never throws).
 * Server route enforces beta eligibility, username, onboarding_completed, and dedup.
 */
export function notifyBetaSignupAfterOnboardingComplete(
  signupMethod = "onboarding"
): void {
  notifyAdminBetaSignup(signupMethod)
}
