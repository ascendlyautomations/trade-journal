/**
 * Pro access: `profiles.is_pro` (manual/admin), complimentary creator access,
 * active/trialing Stripe subscription, a future `trial_end` when webhook
 * status has not synced yet, or unexpired active Early Access.
 */
export function isProActive(
  profile: {
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
  } | null | undefined
): boolean {
  if (profile?.is_pro === true) return true
  if (profile?.creator_access === true) return true
  const status = String(profile?.subscription_status ?? "").toLowerCase().trim()
  if (status === "active" || status === "trialing") return true

  if (
    profile?.early_access_status === "active" &&
    profile.early_access_enrolled_at != null &&
    profile.early_access_started_at != null &&
    profile.early_access_campaign_id === "traxs_pro_for_life_v1" &&
    (profile.early_access_enrollment_source === "standard_email" ||
      profile.early_access_enrollment_source === "standard_oauth")
  ) {
    const earlyAccessEndRaw = profile.early_access_ends_at
    if (earlyAccessEndRaw != null && earlyAccessEndRaw !== "") {
      const earlyAccessEnd = new Date(earlyAccessEndRaw)
      if (
        !Number.isNaN(earlyAccessEnd.getTime()) &&
        earlyAccessEnd > new Date()
      ) {
        return true
      }
    }
  }

  const trialEndRaw = profile?.trial_end
  if (trialEndRaw != null && trialEndRaw !== "") {
    const trialEnd = new Date(trialEndRaw)
    if (!Number.isNaN(trialEnd.getTime()) && trialEnd > new Date()) {
      return true
    }
  }

  return false
}
