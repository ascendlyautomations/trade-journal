import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { resolveDisconnectMemberAccess } from "@/lib/livekit/disconnectMemberAccess.ts"
import { disconnectTradeRoomMemberFromLiveKit } from "@/lib/livekit/disconnectTradeRoomMember.ts"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

type Body = {
  roomId?: string
  userId?: string
}

function parseBody(raw: unknown): Body | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const userId = typeof b.userId === "string" ? b.userId.trim() : ""
  if (!roomId || !userId) return null
  return { roomId, userId }
}

/**
 * Best-effort LiveKit RemoveParticipant after ban/kick (complements DB outbox + cron).
 */
export async function POST(req: Request) {
  const { user } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  if (!isLiveKitConfigured()) {
    return Response.json({ ok: true, skipped: true })
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json({ error: "Invalid JSON body." }, { status: 400 })
  }

  const parsed = parseBody(body)
  if (!parsed) {
    return Response.json(
      { error: "roomId and userId are required." },
      { status: 400 }
    )
  }

  const access = await resolveDisconnectMemberAccess(supabaseServiceRole, {
    actorUserId: user.id,
    roomId: parsed.roomId,
    targetUserId: parsed.userId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  await disconnectTradeRoomMemberFromLiveKit(
    supabaseServiceRole,
    access.roomId,
    access.userId,
    access.userId === user.id ? "leave" : "moderation"
  )

  return Response.json({ ok: true })
}
