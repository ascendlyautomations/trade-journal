import type { SupabaseClient } from "@supabase/supabase-js"
import { isBetaReferralRef } from "@/lib/betaReferralCode"
import { clearStoredReferralCode } from "@/lib/referralPersistence"
import { readStoredReferralCode } from "@/lib/ensureProfileForUser"

function clearStoredReferralCodeIfBeta(): void {
  if (isBetaReferralRef(readStoredReferralCode())) {
    clearStoredReferralCode()
  }
}

/** Clear leftover beta invite codes from storage (enrollment is closed). */
export function clearBetaReferralAfterApply(
  _isBetaTester?: boolean | null
): void {
  clearStoredReferralCodeIfBeta()
}

/**
 * Public beta enrollment is closed. Never applies TRAXBETA10302; only clears
 * leftover stored beta invite codes.
 */
export async function applyBetaReferralIfEligible(
  _supabase: SupabaseClient,
  _userId: string
): Promise<{ applied: boolean }> {
  clearStoredReferralCodeIfBeta()
  return { applied: false }
}
