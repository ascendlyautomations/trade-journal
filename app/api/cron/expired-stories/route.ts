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

/** Vercel Cron — deletes story rows older than 24 hours and their story-bucket media. */
export async function GET(req: Request) {
  if (!isAuthorizedCron(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const result = await purgeExpiredStories(supabaseServiceRole)
  return Response.json({ ok: true, ...result })
}
