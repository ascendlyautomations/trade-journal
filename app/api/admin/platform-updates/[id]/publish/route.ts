import { requireAdminApiUser } from "@/lib/requireAdminApi"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  getPlatformUpdateBroadcast,
  publishPlatformUpdateNow,
} from "@/lib/server/platformUpdates/platformUpdateService"
import { platformUpdateDestinationHref } from "@/lib/platformUpdateDestinations"

export const runtime = "nodejs"

type RouteContext = { params: Promise<{ id: string }> }

export async function POST(req: Request, context: RouteContext) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error

  const { id } = await context.params
  const result = await publishPlatformUpdateNow({
    supabase: supabaseServiceRole,
    updateId: id.trim(),
    adminUserId: auth.adminUser.id,
  })

  if (!result.ok) {
    return Response.json({ error: result.reason }, { status: 409 })
  }

  const broadcast = await getPlatformUpdateBroadcast(
    supabaseServiceRole,
    result.update.id
  )

  return Response.json({
    ok: true,
    update: {
      id: result.update.id,
      title: result.update.title,
      status: result.update.status,
      publishedAt: result.update.published_at,
      sendPush: result.update.send_push,
      destinationHref: platformUpdateDestinationHref(result.update.destination),
    },
    broadcast: broadcast
      ? {
          id: broadcast.id,
          status: broadcast.status,
          attemptedCount: broadcast.attempted_count,
          successCount: broadcast.success_count,
          failedCount: broadcast.failed_count,
        }
      : null,
    broadcastQueued: Boolean(result.broadcastId),
  })
}
