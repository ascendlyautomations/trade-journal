/**
 * Historical beta invite code. Public enrollment is closed — this code must not
 * grant `is_beta_tester` / `is_pro` for new users. Kept only to recognize leftover
 * `?ref=` / `referred_by` values (e.g. skip affiliate checkout, subscription
 * exempt for already-attributed testers).
 */
export const BETA_REFERRAL_CODE = "TRAXBETA10302"

/** Public beta signup / code redeem is closed. */
export const BETA_ENROLLMENT_OPEN = false

export function isBetaReferralRef(ref: string | null | undefined): boolean {
  return ref != null && ref.trim().toUpperCase() === BETA_REFERRAL_CODE
}
