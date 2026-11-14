import {
  runWeeklyTradingReportPushCron,
  runWeeklyTradingReportPushForUser,
} from "@/lib/server/tradingReports/weeklyTradingReportPushCron"

export const runtime = "nodejs"
export const maxDuration = 60

function isAuthorizedCron(req: Request): boolean {
  const secret = process.env.CRON_SECRET?.trim()
  if (!secret) return false
  const auth = req.headers.get("authorization") ?? ""
  return auth === `Bearer ${secret}`
}

/** Supabase pg_cron (Sat 17:00 and 18:00 UTC) — weekly trading report push. */
export async function GET(req: Request) {
  if (!isAuthorizedCron(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  // Temporary single-account production test. Removed after the controlled run.
  const onlyUserId = new URL(req.url).searchParams.get("userId")?.trim() ?? ""
  if (onlyUserId) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(onlyUserId)) {
      return Response.json({ error: "Invalid user" }, { status: 400 })
    }
    const result = await runWeeklyTradingReportPushForUser(onlyUserId)
    return Response.json({ ok: true, scope: "single_user", ...result })
  }

  const result = await runWeeklyTradingReportPushCron()
  return Response.json({ ok: true, ...result })
}
