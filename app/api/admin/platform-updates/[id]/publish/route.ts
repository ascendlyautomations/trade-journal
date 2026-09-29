import { requireAdminApiUser } from "@/lib/requireAdminApi"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  getPlatformUpdateBroadcast,
  publishPlatformUpdateNow,
} from "@/lib/server/platformUpdates/platformUpdateService"
import { deliverPlatformUpdateBroadcastNow } from "@/lib/server/platformUpdates/broadcastWorker"
import { getApnsRuntimeInfo } from "@/lib/server/push/apns"
import { platformUpdateDestinationHref } from "@/lib/platformUpdateDestinations"

export const runtime = "nodejs"
export const maxDuration = 60

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

  let pushDelivery: Awaited<
    ReturnType<typeof deliverPlatformUpdateBroadcastNow>
  > | null = null

  if (result.update.send_push) {
    if (result.broadcastId) {
      pushDelivery = await deliverPlatformUpdateBroadcastNow(result.broadcastId)
    } else {
      const apns = getApnsRuntimeInfo()
      pushDelivery = {
        broadcastId: "",
        status: "failed",
        attemptedCount: 0,
        successCount: 0,
        failedCount: 0,
        apnsConfigured: apns.configured,
        apnsProduction: apns.production,
        apnsBundleId: apns.bundleId,
        iosTokenRows: 0,
        incomplete: false,
        lastApnsFailureReason: "broadcast_row_not_created",
      }
    }
  }

  const broadcast = await getPlatformUpdateBroadcast(
    supabaseServiceRole,
    result.update.id
  )

  const publishSucceeded = true
  const pushSucceeded =
    !result.update.send_push ||
    (pushDelivery != null &&
      pushDelivery.successCount > 0 &&
      pushDelivery.status !== "failed")

  return Response.json({
    ok: true,
    publishSucceeded,
    pushSucceeded,
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
    pushDelivery,
  })
}
