import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { muteLiveKitGeneralVoiceParticipantMicrophone } from "@/lib/livekit/liveKitRoomService.ts"
import { resolveGeneralVoiceModerationAccess } from "@/lib/livekit/generalVoiceModerationAccess.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

function parseBody(raw: unknown): { roomId: string; targetUserId: string; muted: boolean } | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const targetUserId = typeof b.targetUserId === "string" ? b.targetUserId.trim() : ""
  if (!roomId || !targetUserId) return null
  return { roomId, targetUserId, muted: b.muted !== false }
}

export async function POST(req: Request) {
  const { user } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  if (!isLiveKitConfigured()) {
    return Response.json(
      { error: "Live voice is not configured on the server." },
      { status: 503 }
    )
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
      { error: "roomId and targetUserId are required." },
      { status: 400 }
    )
  }

  const access = await resolveGeneralVoiceModerationAccess(supabaseServiceRole, {
    actorUserId: user.id,
    roomId: parsed.roomId,
    targetUserId: parsed.targetUserId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  try {
    await muteLiveKitGeneralVoiceParticipantMicrophone(
      access.roomId,
      access.targetUserId,
      parsed.muted
    )
  } catch (err) {
    console.error("[livekit/voice/mute] failed", err)
    return Response.json({ error: "Could not mute participant." }, { status: 502 })
  }

  return Response.json({ ok: true })
}
