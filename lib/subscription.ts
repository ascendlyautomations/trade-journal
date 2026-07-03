/**
 * Pro access: `profiles.is_pro` (manual/admin), active/trialing Stripe subscription,
 * or a future `trial_end` when webhook status has not synced yet.
 */
export function isProActive(
  profile: {
    is_pro?: boolean | null
    subscription_status?: string | null
    trial_end?: string | null
  } | null | undefined
): boolean {
  if (profile?.is_pro === true) return true
  const status = String(profile?.subscription_status ?? "").toLowerCase().trim()
  if (status === "active" || status === "trialing") return true

  const trialEndRaw = profile?.trial_end
  if (trialEndRaw != null && trialEndRaw !== "") {
    const trialEnd = new Date(trialEndRaw)
    if (!Number.isNaN(trialEnd.getTime()) && trialEnd > new Date()) {
      return true
    }
  }

  return false
}
