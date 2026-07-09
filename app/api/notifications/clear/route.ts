import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { NOTIFICATION_INBOX_TYPES } from "@/lib/notificationEngagementTypes"
import { jsonUserFacingError } from "@/lib/userFacingError"

export async function DELETE(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { error } = await supabaseServiceRole
    .from("notifications")
    .delete()
    .eq("user_id", user.id)
    .in("type", [...NOTIFICATION_INBOX_TYPES])

  if (error) {
    return jsonUserFacingError(error, 500, "[api/notifications/clear]")
  }

  return Response.json({ ok: true })
}
