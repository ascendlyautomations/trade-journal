import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { setLiveKitStagePublish } from "@/lib/livekit/liveKitRoomService.ts"
import { resolveStageModerationAccess } from "@/lib/livekit/stageModerationAccess.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

type Body = {
  roomId?: string
  sectionId?: string
  targetUserId?: string
}

function parseBody(raw: unknown): Body | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const sectionId = typeof b.sectionId === "string" ? b.sectionId.trim() : ""
  const targetUserId =
    typeof b.targetUserId === "string" ? b.targetUserId.trim() : ""
  if (!roomId || !sectionId || !targetUserId) return null
  return { roomId, sectionId, targetUserId }
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
      { error: "roomId, sectionId, and targetUserId are required." },
      { status: 400 }
    )
  }

  const access = await resolveStageModerationAccess(supabaseServiceRole, {
    actorUserId: user.id,
    roomId: parsed.roomId,
    sectionId: parsed.sectionId,
    targetUserId: parsed.targetUserId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  try {
    await setLiveKitStagePublish(
      access.roomId,
      access.sectionId,
      access.targetUserId,
      true
    )
  } catch (err) {
    console.error("[livekit/stage/promote] failed", err)
    return Response.json(
      { error: "Could not promote speaker on live stage." },
      { status: 502 }
    )
  }

  return Response.json({ ok: true, role: "speaker" as const })
}
