import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { getLiveKitBroadcastRoomPresence } from "@/lib/livekit/liveKitRoomService.ts"
import {
  getIngressInfo,
  ingressStatusLabel,
  isIngressWaitingForEncoder,
} from "@/lib/livekit/liveKitIngressService.ts"
import { IngressState_Status } from "@livekit/protocol"
import { resolveTradeRoomBroadcastControlAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import {
  getActiveTradeRoomBroadcast,
  updateBroadcastIngressSnapshot,
} from "@/lib/livekit/tradeRoomBroadcastSession.ts"

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
  const sessionId = url.searchParams.get("sessionId")?.trim() ?? ""
  if (!roomId || !sessionId) {
    return Response.json(
      { error: "roomId and sessionId are required." },
      { status: 400 }
    )
  }

  const access = await resolveTradeRoomBroadcastControlAccess(supabaseServiceRole, {
    userId: user.id,
    roomId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  const active = await getActiveTradeRoomBroadcast(supabaseServiceRole, roomId, {
    skipRecoverStale: true,
    activeScope: "any",
  })

  if (!active || active.id !== sessionId) {
    return Response.json(
      { error: "No active broadcast session found for this room." },
      { status: 404 }
    )
  }

  if (active.broadcasterUserId !== user.id) {
    return Response.json(
      { error: "Only the authorized broadcaster can read OBS ingress status." },
      { status: 403 }
    )
  }

  let hostConnected: boolean | null = null
  let primaryMediaPublisherConnected: boolean | null = null
  let broadcasterConnected: boolean | null = null

  if (isLiveKitConfigured()) {
    const presence = await getLiveKitBroadcastRoomPresence(
      roomId,
      active.broadcasterUserId,
      { primaryMediaPublisherIdentity: active.primaryMediaPublisherIdentity }
    )
    if (presence) {
      hostConnected = presence.hostConnected
      primaryMediaPublisherConnected = presence.primaryMediaPublisherConnected
      broadcasterConnected = presence.broadcasterConnected
    }
  }

  let ingressStatusSnapshot = active.ingressStatusSnapshot
  let ingressWaitingForObs = false
  let ingressDisconnectedOrEnded = false
  const ingressId = active.livekitIngressId?.trim() || ""

  if (ingressId) {
    const infoRes = await getIngressInfo(ingressId)
    if (infoRes.ok && infoRes.info) {
      const label = ingressStatusLabel(infoRes.info)
      ingressStatusSnapshot = label
      ingressWaitingForObs = isIngressWaitingForEncoder(infoRes.info)
      const st = infoRes.info.state?.status
      ingressDisconnectedOrEnded =
        st === IngressState_Status.ENDPOINT_COMPLETE ||
        st === IngressState_Status.ENDPOINT_ERROR
      if (label && label !== active.ingressStatusSnapshot) {
        await updateBroadcastIngressSnapshot(supabaseServiceRole, {
          roomId,
          sessionId: active.id,
          ingressStatusLabel: label,
        })
      }
    } else if (infoRes.ok && !infoRes.info) {
      ingressDisconnectedOrEnded = true
      ingressStatusSnapshot = active.ingressStatusSnapshot
    }
  }

  const broadcastSessionActive = Boolean(active.id)

  return Response.json({
    broadcastSessionId: active.id,
    broadcastSource: active.broadcastSource,
    primaryMediaPublisherIdentity: active.primaryMediaPublisherIdentity,
    livekitIngressId: ingressId || null,
    ingressStatusSnapshot,
    hostConnected,
    primaryMediaPublisherConnected,
    broadcasterConnected,
    broadcastSessionActive,
    ingressWaitingForObs,
    ingressDisconnectedOrEnded,
  })
}
