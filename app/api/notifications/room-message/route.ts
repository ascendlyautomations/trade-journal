import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import { notify } from "@/lib/server/notifications/NotificationService"

/**
 * Trade Room message fanout:
 * - @mentions → Activity (`room_mention`) + Activity push
 * - other members → Messaging push only (no Activity row)
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
    type: "room_message",
    actorUserId: user.id,
    messageId,
  })

  if (!result.ok) {
    return Response.json(
      { error: result.error ?? "Room message notify failed" },
      { status: result.status ?? 500 }
    )
  }

  return Response.json({
    ok: true,
    mentionsInserted: result.mentionsInserted ?? 0,
    messagingPushed: result.messagingPushed ?? 0,
  })
}
