import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { getApnsRuntimeInfo } from "@/lib/server/push/apns"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/**
 * Authenticated APNs / device-token health check (no secrets).
 * Used to verify Sprint 2 push infrastructure without a settings UI.
 *
 * TEMPORARY: `env` diagnostics — remove after APNs E2E verification.
 */
export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const apns = getApnsRuntimeInfo()

  const { count, error } = await supabaseServiceRole
    .from("device_push_tokens")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.id)
    .eq("platform", "ios")

  if (error) {
    console.error("[api/push/status] token count failed", error)
    return Response.json({ error: error.message }, { status: 500 })
  }

  return Response.json({
    ok: true,
    apns: {
      configured: apns.configured,
      production: apns.production,
      bundleId: apns.bundleId,
    },
    // TEMPORARY diagnostics — booleans only; never expose secret values.
    env: {
      hasKeyId: Boolean(process.env.APNS_KEY_ID?.trim()),
      hasTeamId: Boolean(process.env.APNS_TEAM_ID?.trim()),
      hasPrivateKey: Boolean(process.env.APNS_PRIVATE_KEY?.trim()),
    },
    deviceTokenCount: count ?? 0,
    readyToDeliver: apns.configured && (count ?? 0) > 0,
  })
}
