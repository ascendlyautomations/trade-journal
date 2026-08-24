import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import { notify } from "@/lib/server/notifications/NotificationService"

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

  const result = await notify({
    type: "trading_report",
    actorUserId: user.id,
    periodKey: body.periodKey ?? "",
    periodId: body.periodId ?? "",
    kind: body.kind,
    title: body.title,
    href: body.href,
  })

  if (!result.ok) {
    return Response.json(
      { error: result.error ?? "Trading report notify failed" },
      { status: result.status ?? 500 }
    )
  }

  return Response.json({
    ok: true,
    skipped: result.skipped,
    reason: result.reason,
  })
}
