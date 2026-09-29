import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  publishDueScheduledPlatformUpdates,
} from "@/lib/server/platformUpdates/platformUpdateService"
import { processPlatformUpdateBroadcasts } from "@/lib/server/platformUpdates/broadcastWorker"

export const runtime = "nodejs"
export const maxDuration = 60

function isAuthorizedCron(req: Request): boolean {
  const secret = process.env.CRON_SECRET?.trim()
  if (!secret) return false
  const auth = req.headers.get("authorization") ?? ""
  return auth === `Bearer ${secret}`
}

/** Publishes due scheduled updates and continues batched broadcast jobs. */
export async function GET(req: Request) {
  if (!isAuthorizedCron(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const published = await publishDueScheduledPlatformUpdates(supabaseServiceRole)
  const broadcast = await processPlatformUpdateBroadcasts()

  return Response.json({
    ok: true,
    scheduledPublished: published.published,
    broadcast,
  })
}
