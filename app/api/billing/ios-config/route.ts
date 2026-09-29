import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadMonetizationConfigSnapshot } from "@/lib/server/monetizationConfig"

export const runtime = "nodejs"

/**
 * Authenticated iOS monetization flags.
 * The signed-in user id is the override key. Missing config stays false.
 */
export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const snapshot = await loadMonetizationConfigSnapshot(supabaseServiceRole, user.id)

  return Response.json({
    iosPaywallEnabled: snapshot.flags.iosPaywallEnabled,
    entitlementEnforcementEnabled: snapshot.flags.entitlementEnforcementEnabled,
    settingsPresent: snapshot.settingsPresent,
    globalIosPaywallEnabled: snapshot.globalIosPaywallEnabled,
    accountIosPaywallOverride: snapshot.accountIosPaywallOverride,
    fetchedAt: new Date().toISOString(),
  })
}
