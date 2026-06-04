/**
 * Pro access: `profiles.is_pro` (manual/admin) or active/trialing Stripe subscription.
 */
export function isProActive(
  profile: {
    is_pro?: boolean | null
    subscription_status?: string | null
  } | null | undefined
): boolean {
  if (profile?.is_pro === true) return true
  const status = String(profile?.subscription_status ?? "").toLowerCase().trim()
  return status === "active" || status === "trialing"
}
