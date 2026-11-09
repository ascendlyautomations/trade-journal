import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { countLiveKitGeneralVoicePresence } from "@/lib/livekit/liveKitRoomService.ts"
import { resolveTradeRoomLiveVoiceAccess } from "@/lib/livekit/tradeRoomLiveVoiceAccess.ts"

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

  const access = await resolveTradeRoomLiveVoiceAccess(supabaseServiceRole, {
    userId: user.id,
    roomId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  if (!isLiveKitConfigured()) {
    return Response.json({
      connectedCount: 0,
      speakingCount: 0,
      configured: false,
    })
  }

  const presence = await countLiveKitGeneralVoicePresence(roomId)
  if (!presence) {
    return Response.json(
      { error: "Could not read General Voice presence." },
      { status: 503 }
    )
  }

  return Response.json({
    connectedCount: presence.connectedCount,
    speakingCount: presence.speakingCount,
    configured: true,
  })
}
