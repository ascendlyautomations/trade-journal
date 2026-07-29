import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { getApnsRuntimeInfo } from "@/lib/server/push/apns"

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

  // TEMPORARY [tt-push-debug]
  console.info("[tt-push-debug] push status", {
    userId: user.id,
    tokenCount: tokens.length,
    deviceTokens: tokens.map((t) => t.deviceToken),
    apnsEnvironment: apns.production ? "production" : "sandbox",
    bundleId: apns.bundleId,
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
    // TEMPORARY [tt-push-debug] — full tokens for phone↔DB comparison.
    debug: {
      userId: user.id,
      tokens,
    },
  })
}
