import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { entitlementEnforcementEnabled } from "@/lib/server/monetizationConfig"
import {
  loadProEntitlementProfile,
  requireProEntitlement,
  type ProEntitlementCheck,
} from "@/lib/server/requireProEntitlement"

/**
 * Central gate for OpenAI-backed BFF routes.
 *
 * Follows `entitlement_enforcement_enabled`. When that flag is false, or the
 * config cannot be read, authenticated users pass. When it is true, TraxPro
 * is required.
 */
export async function requireAIFeatureEntitlement(
  userId: string,
  options?: {
    error?: string
    reply?: string
  }
): Promise<ProEntitlementCheck> {
  const enforced = await entitlementEnforcementEnabled(supabaseServiceRole)
  if (!enforced) {
    return loadProEntitlementProfile(userId)
  }
  return requireProEntitlement(userId, options)
}
