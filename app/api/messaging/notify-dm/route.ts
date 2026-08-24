import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import { notify } from "@/lib/server/notifications/NotificationService"

/**
 * Direct Message / conversation push — Messaging only (never Activity).
 */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let messageId: string | undefined
  try {
    const body = (await req.json()) as { messageId?: string }
    messageId = body.messageId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!messageId) {
    return Response.json({ error: "Invalid messageId" }, { status: 400 })
  }

  const result = await notify({
    type: "dm_message",
    actorUserId: user.id,
    messageId,
  })

  if (!result.ok) {
    return Response.json(
      { error: result.error ?? "DM notify failed" },
      { status: result.status ?? 500 }
    )
  }

  return Response.json({
    ok: true,
    pushed: result.pushed ?? 0,
    skipped: result.skipped,
  })
}
