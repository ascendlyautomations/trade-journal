import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadMonetizationConfigSnapshot } from "@/lib/server/monetizationConfig"

export const runtime = "nodejs"

/** Authenticated monetization flags for web and iOS clients. Missing config stays false. */
export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const snapshot = await loadMonetizationConfigSnapshot(
    supabaseServiceRole,
    user.id
  )

  return Response.json({
    iosPaywallEnabled: snapshot.flags.iosPaywallEnabled,
    webPaywallEnabled: snapshot.flags.webPaywallEnabled,
    entitlementEnforcementEnabled: snapshot.flags.entitlementEnforcementEnabled,
    settingsPresent: snapshot.settingsPresent,
    globalIosPaywallEnabled: snapshot.globalIosPaywallEnabled,
    accountIosPaywallOverride: snapshot.accountIosPaywallOverride,
    fetchedAt: new Date().toISOString(),
  })
}
