/**
 * Pro access: `profiles.is_pro` (manual/admin) or active Stripe subscription.
 */
export function isProActive(
  profile: {
    is_pro?: boolean | null
    subscription_status?: string | null
  } | null | undefined
): boolean {
  if (profile?.is_pro === true) return true
  return profile?.subscription_status === "active"
}
