import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { jsonUserFacingError } from "@/lib/userFacingError"

type NotifyBody = {
  periodKey?: string
  periodId?: string
  kind?: "weekly" | "monthly"
  title?: string
  href?: string
}

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: NotifyBody
  try {
    body = (await req.json()) as NotifyBody
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const periodKey = body.periodKey?.trim()
  const periodId = body.periodId?.trim()
  const kind = body.kind === "monthly" ? "monthly" : "weekly"
  const title =
    body.title?.trim() ||
    (kind === "weekly"
      ? "Your Weekly Trading Report is Ready"
      : "Your Monthly Trading Report is Ready")
  const href = body.href?.trim() || `/dashboard?report=${encodeURIComponent(periodKey || "weekly_last")}`

  if (!periodKey || !periodId) {
    return Response.json({ error: "Missing periodKey or periodId" }, { status: 400 })
  }

  const content = JSON.stringify({
    title,
    body:
      kind === "weekly"
        ? "Your weekly trading summary is ready to review."
        : "Your monthly trading summary is ready to review.",
    href,
    periodKey,
    periodId,
    kind,
  })

  const dedupeToken = `${periodId}:${periodKey}`

  const { data: existing, error: existingErr } = await supabaseServiceRole
    .from("notifications")
    .select("id")
    .eq("user_id", user.id)
    .eq("type", "trading_report")
    .ilike("content", `%${periodId}%`)
    .limit(1)

  if (existingErr) {
    return jsonUserFacingError(existingErr, 500, "[api/trading-reports/notify] dedupe")
  }

  if (existing && existing.length > 0) {
    return Response.json({ ok: true, skipped: true, dedupeToken })
  }

  const { error } = await supabaseServiceRole.from("notifications").insert({
    user_id: user.id,
    sender_id: null,
    type: "trading_report",
    content,
    read: false,
  })

  if (error) {
    return jsonUserFacingError(error, 500, "[api/trading-reports/notify] insert")
  }

  const { scheduleIosPushDelivery } = await import(
    "@/lib/server/push/deliverPushNotification"
  )
  scheduleIosPushDelivery({
    recipientUserId: user.id,
    type: "trading_report",
    sender_id: null,
    content,
    prefsAlreadyChecked: true,
  })

  return Response.json({ ok: true })
}
