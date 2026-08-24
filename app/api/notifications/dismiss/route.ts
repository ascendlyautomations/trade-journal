import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { jsonUserFacingError } from "@/lib/userFacingError"
import { invalidateAppIconBadgeCache } from "@/lib/server/push/badgeService"

export async function DELETE(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let ids: string[] = []
  try {
    const body = (await req.json()) as { ids?: string[] }
    ids = Array.isArray(body.ids)
      ? body.ids.map((id) => String(id).trim()).filter(Boolean)
      : []
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (ids.length === 0) {
    return Response.json({ error: "No notification ids provided" }, { status: 400 })
  }

  const { error } = await supabaseServiceRole
    .from("notifications")
    .delete()
    .eq("user_id", user.id)
    .in("id", ids)

  if (error) {
    return jsonUserFacingError(error, 500, "[api/notifications/dismiss]")
  }

  invalidateAppIconBadgeCache(user.id)
  return Response.json({ ok: true })
}
