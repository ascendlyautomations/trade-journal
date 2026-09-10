import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadTraxProEntitlementSnapshot } from "@/lib/traxProEntitlement"

export const runtime = "nodejs"

/**
 * Authoritative TraxPro entitlement for the authenticated user.
 * Combines Stripe/profile fields, Apple subscriptions, and special grants.
 */
export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const loaded = await loadTraxProEntitlementSnapshot(supabaseServiceRole, user.id)
  if (!loaded.ok) {
    return Response.json({ error: loaded.reason }, { status: 500 })
  }

  const { snapshot } = loaded

  return Response.json({
    traxProActive: snapshot.traxProActive,
    source: snapshot.source,
    plan: snapshot.traxProActive ? "pro" : "free",
    billingInterval: snapshot.billingInterval,
    subscriptionStatus: snapshot.subscriptionStatus,
    trialEndsAt: snapshot.trialEndsAt,
    currentPeriodEndsAt: snapshot.currentPeriodEndsAt,
    cancelAtPeriodEnd: snapshot.cancelAtPeriodEnd,
    appleExpiresAt: snapshot.appleExpiresAt,
    appleProductId: snapshot.appleSubscription?.product_id ?? null,
  })
}
