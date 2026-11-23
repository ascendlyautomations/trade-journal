import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { entitlementEnforcementEnabled } from "@/lib/server/monetizationConfig"
import {
  loadProEntitlementProfile,
  requireProEntitlement,
  type ProEntitlementCheck,
} from "@/lib/server/requireProEntitlement"

/**
 * BFF routes for TraxPro-only product features (non-AI).
 * When `entitlement_enforcement_enabled` is off, authenticated users pass (same as AI routes).
 */
export async function requireTraxProFeatureEntitlement(
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