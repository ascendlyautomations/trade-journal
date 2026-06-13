export const BETA_REFERRAL_CODE = "TRAXBETA10302"

export function isBetaReferralRef(ref: string | null | undefined): boolean {
  return ref != null && ref.trim().toUpperCase() === BETA_REFERRAL_CODE
}
