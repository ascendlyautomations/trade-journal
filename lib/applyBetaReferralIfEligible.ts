import type { SupabaseClient } from "@supabase/supabase-js"
import { BETA_REFERRAL_CODE, isBetaReferralRef } from "@/lib/betaReferralCode"
import {
  clearStoredReferralCode,
} from "@/lib/referralPersistence"
import { readStoredReferralCode } from "@/lib/ensureProfileForUser"

function clearStoredReferralCodeIfBeta(): void {
  if (isBetaReferralRef(readStoredReferralCode())) {
    clearStoredReferralCode()
  }
}

/** Clear beta referral from storage after flags are confirmed on profile. */
export function clearBetaReferralAfterApply(isBetaTester: boolean | null | undefined): void {
  if (isBetaTester === true) {
    clearStoredReferralCodeIfBeta()
  }
}

/**
 * Backfill beta access for OAuth users whose profile was created without referred_by.
 * DB trigger sets is_beta_tester + is_pro when referred_by = TRAXBETA10302.
 */
export async function applyBetaReferralIfEligible(
  supabase: SupabaseClient,
  userId: string
): Promise<{ applied: boolean }> {
  const storedRef = readStoredReferralCode()
  if (!isBetaReferralRef(storedRef)) {
    return { applied: false }
  }

  const { data: profile, error } = await supabase
    .from("profiles")
    .select("is_beta_tester, referred_by")
    .eq("id", userId)
    .maybeSingle()

  if (error || !profile) {
    if (error) console.error("applyBetaReferralIfEligible fetch:", error)
    return { applied: false }
  }

  if (profile.is_beta_tester === true) {
    clearStoredReferralCodeIfBeta()
    return { applied: false }
  }

  const referredBy = profile.referred_by != null ? String(profile.referred_by).trim() : ""
  if (referredBy) {
    return { applied: false }
  }

  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    return { applied: false }
  }

  const res = await fetch("/api/profile/apply-beta-referral", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ code: BETA_REFERRAL_CODE }),
  })

  if (!res.ok) {
    const payload = (await res.json().catch(() => null)) as { error?: string } | null
    console.error(
      "applyBetaReferralIfEligible update:",
      payload?.error ?? res.statusText
    )
    return { applied: false }
  }

  clearStoredReferralCode()
  return { applied: true }
}
