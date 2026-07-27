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
    deviceTokenCount: count ?? 0,
    readyToDeliver: apns.configured && (count ?? 0) > 0,
  })
}
