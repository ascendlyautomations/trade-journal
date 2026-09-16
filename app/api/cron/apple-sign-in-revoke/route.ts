import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { processAppleSignInRevokeQueue } from "@/lib/appleSignInRevokeQueueWorker"

export const runtime = "nodejs"
export const maxDuration = 60

function isAuthorizedCron(req: Request): boolean {
  const secret = process.env.CRON_SECRET?.trim()
  if (!secret) return false
  const auth = req.headers.get("authorization") ?? ""
  return auth === `Bearer ${secret}`
}

/** Vercel Cron — drains apple_sign_in_revoke_queue (service role, bounded batch). */
export async function GET(req: Request) {
  if (!isAuthorizedCron(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const result = await processAppleSignInRevokeQueue(supabaseServiceRole)
  return Response.json({ ok: true, ...result })
}
