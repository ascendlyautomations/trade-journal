import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { purgeExpiredStories } from "@/lib/expiredStoryCleanup"

export const runtime = "nodejs"
export const maxDuration = 60

function isAuthorizedCron(req: Request): boolean {
  const secret = process.env.CRON_SECRET?.trim()
  if (!secret) return false
  const auth = req.headers.get("authorization") ?? ""
  return auth === `Bearer ${secret}`
}

/**
 * Vercel Cron — expires story media after 24h and purges owner metadata after +30 days.
 * Schedule: `vercel.json` → `15 7 * * *` (once daily). Hobby-tier plans usually cannot run
 * more often; Pro can use e.g. `15 7,19 * * *` to shorten public-bucket URL exposure until
 * the stories bucket is made private with signed URLs (see docs/STORY_ENGAGEMENT_DEPLOYMENT.md).
 */
export async function GET(req: Request) {
  if (!isAuthorizedCron(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const result = await purgeExpiredStories(supabaseServiceRole)
  return Response.json({ ok: true, ...result })
}
