import { isBetaReferralRef } from "@/lib/betaReferralCode"

/** localStorage key used across signup, checkout, and OAuth flows. */
export const REFERRAL_CODE_STORAGE_KEY = "referral_code"

/** Persist `?ref=` from the current or provided query string. Returns stored value. */
export function persistReferralCodeFromUrl(search?: string): string | null {
  if (typeof window === "undefined") return null

  const query = search ?? window.location.search
  const ref = new URLSearchParams(query).get("ref")
  const trimmed = ref?.trim()
  if (!trimmed) return null

  // Closed beta invite — do not persist or attribute as a referral.
  if (isBetaReferralRef(trimmed)) {
    clearStoredReferralCode()
    return null
  }

  try {
    localStorage.setItem(REFERRAL_CODE_STORAGE_KEY, trimmed)
  } catch {
    /* ignore quota / private mode */
  }

  return trimmed
}

export function clearStoredReferralCode(): void {
  if (typeof window === "undefined") return
  try {
    localStorage.removeItem(REFERRAL_CODE_STORAGE_KEY)
  } catch {
    /* ignore */
  }
}
