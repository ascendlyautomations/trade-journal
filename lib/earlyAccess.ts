export const EARLY_ACCESS_CAMPAIGN_KEY = "traxs_pro_for_life_v1"
export const EARLY_ACCESS_DURATION_DAYS = 21
export const EARLY_ACCESS_REFERRAL_BASE_URL = "https://tradetraxs.com"
const EARLY_ACCESS_OAUTH_SIGNUP_PENDING_KEY =
  "tt_early_access_oauth_signup_pending"

export function generateEarlyAccessReferralCode(): string {
  return Math.random().toString(36).substring(2, 8).toUpperCase()
}

export type EarlyAccessStatus =
  | "active"
  | "expired"
  | "converted_lifetime"
  | "ineligible"

export type EarlyAccessProgress = {
  status: EarlyAccessStatus | null
  enrolledAt: string | null
  endsAt: string | null
  followCount: number
  publicTradeDayCount: number
  referralCount: number
  completedCount: number
  allComplete: boolean
  awardLimit: number
  awardsClaimed: number
  spotsRemaining: number
  alreadyAwarded: boolean
}

export type ProForLifeClaimResult =
  | "awarded"
  | "already_awarded"
  | "incomplete"
  | "expired"
  | "sold_out"
  | "ineligible"

export function isEarlyAccessActive(profile: {
  early_access_enrolled_at?: string | null
  early_access_started_at?: string | null
  early_access_status?: string | null
  early_access_ends_at?: string | null
  early_access_campaign_id?: string | null
  early_access_enrollment_source?: string | null
} | null | undefined): boolean {
  if (profile?.early_access_status !== "active") return false
  if (!profile.early_access_enrolled_at || !profile.early_access_started_at) {
    return false
  }
  if (profile.early_access_campaign_id !== EARLY_ACCESS_CAMPAIGN_KEY) {
    return false
  }
  if (
    profile.early_access_enrollment_source !== "standard_email" &&
    profile.early_access_enrollment_source !== "standard_oauth"
  ) {
    return false
  }
  const raw = profile.early_access_ends_at
  if (!raw) return false
  const endsAt = new Date(raw)
  return !Number.isNaN(endsAt.getTime()) && endsAt.getTime() > Date.now()
}

export function buildEarlyAccessReferralLink(
  referralCode: string | null | undefined,
  baseUrl = EARLY_ACCESS_REFERRAL_BASE_URL
): string {
  const code = String(referralCode ?? "").trim()
  if (!code) return ""
  return `${baseUrl.replace(/\/$/, "")}/login?tab=signup&ref=${encodeURIComponent(
    code
  )}`
}

export function earlyAccessDaysRemaining(
  endsAt: string | null | undefined,
  now = new Date()
): number {
  if (!endsAt) return 0
  const end = new Date(endsAt)
  if (Number.isNaN(end.getTime())) return 0
  return Math.max(
    0,
    Math.ceil((end.getTime() - now.getTime()) / (24 * 60 * 60 * 1000))
  )
}

export function markEarlyAccessOAuthSignupPending(): void {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(EARLY_ACCESS_OAUTH_SIGNUP_PENDING_KEY, "1")
  } catch {
    /* session storage unavailable */
  }
}

export function hasEarlyAccessOAuthSignupPending(): boolean {
  if (typeof window === "undefined") return false
  try {
    return sessionStorage.getItem(EARLY_ACCESS_OAUTH_SIGNUP_PENDING_KEY) === "1"
  } catch {
    return false
  }
}

export function clearEarlyAccessOAuthSignupPending(): void {
  if (typeof window === "undefined") return
  try {
    sessionStorage.removeItem(EARLY_ACCESS_OAUTH_SIGNUP_PENDING_KEY)
  } catch {
    /* session storage unavailable */
  }
}

export type EarlyAccessDisplayProfile = {
  onboarding_completed?: boolean | null
  early_access_enrolled_at?: string | null
  early_access_started_at?: string | null
  early_access_ends_at?: string | null
  early_access_status?: string | null
  early_access_campaign_id?: string | null
  early_access_enrollment_source?: string | null
  lifetime_access_source?: string | null
  lifetime_access_granted_at?: string | null
  is_pro?: boolean | null
  creator_access?: boolean | null
  is_beta_tester?: boolean | null
  use_free_tier?: boolean | null
  subscription_status?: string | null
  trial_end?: string | null
  stripe_customer_id?: string | null
}

export function shouldShowProForLifeCard(
  profile: EarlyAccessDisplayProfile | null | undefined
): boolean {
  if (!profile || profile.onboarding_completed !== true) return false
  if (!isEarlyAccessActive(profile)) return false
  if (profile.lifetime_access_source || profile.lifetime_access_granted_at) {
    return false
  }

  // Enrollment is the positive signal. These checks prevent corrupted or
  // conflicting legacy entitlements from exposing campaign UI.
  if (
    profile.is_pro === true ||
    profile.creator_access === true ||
    profile.is_beta_tester === true ||
    profile.use_free_tier === true ||
    profile.trial_end != null ||
    profile.stripe_customer_id != null
  ) {
    return false
  }
  const subscriptionStatus = String(
    profile.subscription_status ?? ""
  ).toLowerCase()
  return subscriptionStatus !== "active" && subscriptionStatus !== "trialing"
}
