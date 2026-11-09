import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { resolveDisconnectMemberAccess } from "@/lib/livekit/disconnectMemberAccess.ts"
import { disconnectTradeRoomMemberFromLiveKit } from "@/lib/livekit/disconnectTradeRoomMember.ts"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

type ParsedDisconnectMemberBody = {
  roomId: string
  userId: string
  scope?: "all" | "voice"
}

function parseDisconnectMemberBody(raw: unknown): ParsedDisconnectMemberBody | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const userId = typeof b.userId === "string" ? b.userId.trim() : ""
  const scopeRaw = typeof b.scope === "string" ? b.scope.trim() : ""
  const scope = scopeRaw === "voice" ? "voice" : "all"
  if (!roomId || !userId) return null
  return { roomId, userId, scope }
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

  const parsed = parseDisconnectMemberBody(body)
  if (parsed === null) {
    return Response.json(
      { error: "roomId and userId are required." },
      { status: 400 }
    )
  }

  const { roomId, userId: targetUserId, scope } = parsed

  const access = await resolveDisconnectMemberAccess(supabaseServiceRole, {
    actorUserId: user.id,
    roomId,
    targetUserId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  if (scope === "voice" && access.userId === user.id) {
    return Response.json(
      { error: "Self-disconnect uses the default leave flow." },
      { status: 400 }
    )
  }

  await disconnectTradeRoomMemberFromLiveKit(
    supabaseServiceRole,
    access.roomId,
    access.userId,
    access.userId === user.id ? "leave" : "moderation",
    { scope }
  )

  return Response.json({ ok: true })
}
