import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { countLiveKitBroadcastViewers } from "@/lib/livekit/liveKitRoomService.ts"
import { getActiveTradeRoomBroadcast } from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import { resolveTradeRoomBroadcastViewerAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json(
      { error: "Unauthorized", detail: authError?.code ?? null },
      { status: 401 }
    )
  }

  const url = new URL(req.url)
  const roomId = url.searchParams.get("roomId")?.trim() ?? ""
  if (!roomId) {
    return Response.json({ error: "roomId is required." }, { status: 400 })
  }

  const access = await resolveTradeRoomBroadcastViewerAccess(supabaseServiceRole, {
    userId: user.id,
    roomId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  const active = await getActiveTradeRoomBroadcast(supabaseServiceRole, roomId)
  if (!active) {
    return Response.json({ live: false })
  }

  let viewerCount: number | null = null
  if (isLiveKitConfigured()) {
    viewerCount = await countLiveKitBroadcastViewers(
      roomId,
      active.broadcasterUserId
    )
  }

  return Response.json({
    live: true,
    broadcastSessionId: active.id,
    broadcasterUserId: active.broadcasterUserId,
    broadcasterDisplayName: active.broadcasterDisplayName,
    startedAt: active.startedAt,
    voiceMode: active.voiceMode,
    videoSource: active.videoSource,
    viewerCount,
  })
}
