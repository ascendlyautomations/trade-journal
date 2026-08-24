import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import { notify } from "@/lib/server/notifications/NotificationService"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let roomId: string | undefined
  try {
    const body = (await req.json()) as { roomId?: string }
    roomId = body.roomId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const result = await notify({
    type: "room_join",
    actorUserId: user.id,
    roomId: roomId ?? "",
  })

  if (!result.ok) {
    return Response.json(
      { error: result.error ?? "Room join notify failed" },
      { status: result.status ?? 500 }
    )
  }

  return Response.json({
    ok: true,
    skipped: result.skipped,
    deduplicated: result.deduplicated,
  })
}
