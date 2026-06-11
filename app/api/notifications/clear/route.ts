import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { NOTIFICATION_ENGAGEMENT_TYPES } from "@/lib/notificationEngagementTypes"

export async function DELETE(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { error } = await supabaseServiceRole
    .from("notifications")
    .delete()
    .eq("user_id", user.id)
    .in("type", [...NOTIFICATION_ENGAGEMENT_TYPES])

  if (error) {
    console.error("[api/notifications/clear] delete failed", error)
    return Response.json({ error: error.message }, { status: 500 })
  }

  return Response.json({ ok: true })
}
