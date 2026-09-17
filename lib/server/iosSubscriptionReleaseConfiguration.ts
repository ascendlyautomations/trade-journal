/**
 * Server mirror of native `IosSubscriptionReleaseConfiguration`.
 *
 * When iOS paid subscriptions are disabled for the current release, authenticated
 * users may use included AI features without TraxPro entitlement checks.
 */
export function iosPaidSubscriptionsEnabled(): boolean {
  const raw = process.env.IOS_PAID_SUBSCRIPTIONS_ENABLED?.trim().toLowerCase()
  if (raw === "1" || raw === "true" || raw === "yes") return true
  if (raw === "0" || raw === "false" || raw === "no") return false
  return false
}
