import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { mintLiveKitBroadcastViewerToken } from "@/lib/livekit/mintLiveKitBroadcastToken.ts"
import { getActiveTradeRoomBroadcast } from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import { resolveTradeRoomBroadcastViewerAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import { parseRoomIdBody } from "../_shared.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function POST(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json(
      { error: "Unauthorized", detail: authError?.code ?? null },
      { status: 401 }
    )
  }

  if (!isLiveKitConfigured()) {
    return Response.json(
      { error: "Live streaming is not configured on the server." },
      { status: 503 }
    )
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json({ error: "Invalid JSON body." }, { status: 400 })
  }

  const parsed = parseRoomIdBody(body)
  if (!parsed) {
    return Response.json({ error: "roomId is required." }, { status: 400 })
  }

  const access = await resolveTradeRoomBroadcastViewerAccess(supabaseServiceRole, {
    userId: user.id,
    roomId: parsed.roomId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  const active = await getActiveTradeRoomBroadcast(supabaseServiceRole, parsed.roomId)
  if (!active) {
    return Response.json({ error: "No live stream is active in this room." }, { status: 404 })
  }

  const session = await mintLiveKitBroadcastViewerToken(
    user.id,
    parsed.roomId,
    access.displayName
  )

  if (!session) {
    return Response.json(
      { error: "Could not mint LiveKit viewer token." },
      { status: 503 }
    )
  }

  return Response.json({
    ...session,
    broadcastSessionId: active.id,
    broadcasterUserId: active.broadcasterUserId,
    broadcasterDisplayName: active.broadcasterDisplayName,
    startedAt: active.startedAt,
    voiceMode: active.voiceMode,
    videoSource: active.videoSource,
  })
}
