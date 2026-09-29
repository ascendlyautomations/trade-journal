/**
 * Retired. iOS monetization is `app_monetization_settings`, not this env var.
 * Kept so a leftover `IOS_PAID_SUBSCRIPTIONS_ENABLED` cannot turn gating on
 * beside the database flag.
 */
export function iosPaidSubscriptionsEnabled(): boolean {
  return false
}
