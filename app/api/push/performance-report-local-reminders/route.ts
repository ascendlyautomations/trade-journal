import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

type Body = {
  active?: boolean
  installationId?: string | null
}

/**
 * Marks whether this iOS install has verified local Performance Report reminders scheduled.
 * Scoped to `installation_id` on `device_push_tokens` (row delete on invalid APNs token clears the flag).
 */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: Body
  try {
    body = (await req.json()) as Body
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const active = body.active === true
  const installationId =
    typeof body.installationId === "string"
      ? body.installationId.trim() || null
      : null

  if (!installationId) {
    return Response.json({ error: "installationId is required" }, { status: 400 })
  }

  const now = new Date().toISOString()
  const { data, error } = await supabaseServiceRole
    .from("device_push_tokens")
    .update({
      performance_report_local_reminders_active: active,
      updated_at: now,
    })
    .eq("user_id", user.id)
    .eq("platform", "ios")
    .eq("installation_id", installationId)
    .select("id")

  if (error) {
    console.error(
      "[api/push/performance-report-local-reminders] update failed",
      error
    )
    return Response.json({ error: error.message }, { status: 500 })
  }

  if (!data?.length) {
    return Response.json({ updated: 0, active })
  }

  return Response.json({ updated: data.length, active })
}