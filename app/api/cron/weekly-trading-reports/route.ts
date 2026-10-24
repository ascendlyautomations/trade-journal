import { runWeeklyTradingReportPushCron } from "@/lib/server/tradingReports/weeklyTradingReportPushCron"

export const runtime = "nodejs"
export const maxDuration = 60

function isAuthorizedCron(req: Request): boolean {
  const secret = process.env.CRON_SECRET?.trim()
  if (!secret) return false
  const auth = req.headers.get("authorization") ?? ""
  return auth === `Bearer ${secret}`
}

/** Vercel Cron (Hobby: Sat 17:00 UTC) — weekly trading report push, gated to ET Saturday window. */
export async function GET(req: Request) {
  if (!isAuthorizedCron(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const result = await runWeeklyTradingReportPushCron()
  return Response.json({ ok: true, ...result })
}
