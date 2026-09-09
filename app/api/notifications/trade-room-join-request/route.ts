import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import { notifyTradeRoomJoinRequest } from "@/lib/server/notifications/handlers/tradeRoomJoinRequestNotify"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let roomId: string | undefined
  let requestId: string | undefined
  try {
    const body = (await req.json()) as { roomId?: string; requestId?: string }
    roomId = body.roomId?.trim()
    requestId = body.requestId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!roomId || !requestId) {
    return Response.json({ error: "Invalid roomId or requestId" }, { status: 400 })
  }

  const result = await notifyTradeRoomJoinRequest(user.id, roomId, requestId)
  if (!result.ok) {
    return Response.json(
      { error: result.error ?? "Notify failed" },
      { status: result.status ?? 500 }
    )
  }

  return Response.json({
    ok: true,
    skipped: result.skipped ?? false,
  })
}
