import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { getApnsRuntimeInfo } from "@/lib/server/push/apns"
import { redactDeviceToken } from "@/lib/server/push/deviceTokenRedaction"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/**
 * Authenticated APNs / device-token health check (no secrets).
 */
export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const apns = getApnsRuntimeInfo()

  const { data: rows, error } = await supabaseServiceRole
    .from("device_push_tokens")
    .select("device_token, updated_at, last_seen_at, app_version")
    .eq("user_id", user.id)
    .eq("platform", "ios")

  if (error) {
    console.error("[api/push/status] token lookup failed", error)
    return Response.json({ error: error.message }, { status: 500 })
  }

  const tokens = (rows ?? []).map((row) => ({
    deviceToken: String(row.device_token ?? "").trim(),
    updatedAt: row.updated_at ?? null,
    lastSeenAt: row.last_seen_at ?? null,
    appVersion: row.app_version ?? null,
  }))

  console.info("[api/push/status]", {
    userId: user.id,
    tokenCount: tokens.length,
    deviceTokenPrefixes: tokens.map((t) => redactDeviceToken(t.deviceToken)),
    apnsEnvironment: apns.production ? "production" : "sandbox",
    bundleId: apns.bundleId,
    apnsConfigured: apns.configured,
  })

  return Response.json({
    ok: true,
    apns: {
      configured: apns.configured,
      production: apns.production,
      bundleId: apns.bundleId,
      environment: apns.production ? "production" : "sandbox",
    },
    deviceTokenCount: tokens.length,
    readyToDeliver: apns.configured && tokens.length > 0,
  })
}
