import { iosPaidSubscriptionsEnabled } from "@/lib/server/iosSubscriptionReleaseConfiguration"
import {
  loadProEntitlementProfile,
  requireProEntitlement,
  type ProEntitlementCheck,
} from "@/lib/server/requireProEntitlement"

/**
 * Central gate for OpenAI-backed BFF routes.
 *
 * - Release with paid iOS subscriptions OFF: authenticated users pass (profile must load).
 * - Future paid release: same behavior as `requireProEntitlement()`.
 */
export async function requireAIFeatureEntitlement(
  userId: string,
  options?: {
    error?: string
    reply?: string
  }
): Promise<ProEntitlementCheck> {
  if (!iosPaidSubscriptionsEnabled()) {
    return loadProEntitlementProfile(userId)
  }
  return requireProEntitlement(userId, options)
}
