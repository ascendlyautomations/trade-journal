import type { SupabaseClient } from "@supabase/supabase-js"
import { BETA_REFERRAL_CODE } from "@/lib/betaReferralCode"
import { notifyAdminBetaSignup } from "@/lib/notifyAdminBetaSignup"

const BETA_PROFILE_SELECT = "is_beta_tester, referred_by"

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

/** Reload profile until DB trigger has applied beta flags (or attempts exhausted). */
export async function reloadBetaProfileForNotify(
  supabase: SupabaseClient,
  userId: string,
  maxAttempts = 4
): Promise<{ is_beta_tester: boolean | null; referred_by: string | null } | null> {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const { data, error } = await supabase
      .from("profiles")
      .select(BETA_PROFILE_SELECT)
      .eq("id", userId)
      .maybeSingle()

    if (error) {
      console.error("[beta-signup-email] profile reload failed", { userId, error })
      return null
    }

    if (data && isProfileBetaSignupEligible(data)) {
      return {
        is_beta_tester:
          typeof data.is_beta_tester === "boolean" ? data.is_beta_tester : null,
        referred_by: data.referred_by != null ? String(data.referred_by) : null,
      }
    }

    if (attempt < maxAttempts - 1) {
      await new Promise((resolve) => setTimeout(resolve, 150 * (attempt + 1)))
    }
  }

  return null
}

/** Call admin notify after beta flags are confirmed on profile (never throws). */
export async function notifyBetaSignupWhenReady(
  supabase: SupabaseClient,
  userId: string,
  signupMethod?: string
): Promise<void> {
  const profile = await reloadBetaProfileForNotify(supabase, userId)
  if (!profile) {
    if (process.env.NODE_ENV === "development") {
      console.warn("[beta-signup-email] skipped notify: beta profile not confirmed", {
        userId,
      })
    }
    return
  }

  if (process.env.NODE_ENV === "development") {
    console.log("[beta-signup-email] attempting notify", {
      userId,
      signupMethod: signupMethod ?? null,
      is_beta_tester: profile.is_beta_tester,
      referred_by: profile.referred_by,
    })
  }

  notifyAdminBetaSignup(signupMethod)
}
