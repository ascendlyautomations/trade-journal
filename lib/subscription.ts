/**
 * Pro access is driven by Stripe → profiles.subscription_status.
 * Use this everywhere instead of reading profile.is_pro directly.
 */
export function isProActive(
  profile: { subscription_status?: string | null } | null | undefined
): boolean {
  return profile?.subscription_status === "active"
}
