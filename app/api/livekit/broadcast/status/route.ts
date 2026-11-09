import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { getLiveKitBroadcastRoomPresence } from "@/lib/livekit/liveKitRoomService.ts"
import { getActiveTradeRoomBroadcast } from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import { reconcileTradeRoomBroadcastSession } from "@/lib/livekit/tradeRoomBroadcastReconcile.ts"
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

  const reconcile = url.searchParams.get("reconcile") === "1"
  /** Frequent polls: one cheap Supabase SELECT, no profiles join, no LiveKit (merge preserves viewer count UI). */
  const lite = url.searchParams.get("lite") === "1" && !reconcile

  if (reconcile) {
    await reconcileTradeRoomBroadcastSession(supabaseServiceRole, {
      roomId,
      viewerUserId: user.id,
      endIfBroadcasterAbsent: true,
    })
  }

  const active = await getActiveTradeRoomBroadcast(supabaseServiceRole, roomId, {
    lite,
    skipRecoverStale: lite,
    viewerUserId: user.id,
  })
  if (!active) {
    return Response.json({
      live: false,
      publicLive: false,
      isBroadcaster: false,
    })
  }

  const isBroadcaster = active.broadcasterUserId === user.id
  const publicLive = active.visibility === "public"
  /** Session row exists (including OBS preparing). `publicLive` is discoverable / viewer-accessible. */
  const live =
    publicLive || (active.visibility === "preparing" && isBroadcaster)

  if (lite) {
    return Response.json({
      live,
      publicLive,
      visibility: active.visibility,
      broadcastSessionId: active.id,
      broadcasterUserId: active.broadcasterUserId,
      startedAt: active.startedAt,
      voiceMode: active.voiceMode,
      videoSource: active.videoSource,
      broadcastSource: active.broadcastSource,
      primaryMediaPublisherIdentity: active.primaryMediaPublisherIdentity,
      isBroadcaster,
    })
  }

  let viewerCount: number | null = null
  let broadcasterConnected: boolean | null = null
  let hostConnected: boolean | null = null
  let primaryMediaPublisherConnected: boolean | null = null
  if (isLiveKitConfigured()) {
    const presence = await getLiveKitBroadcastRoomPresence(
      roomId,
      active.broadcasterUserId,
      { primaryMediaPublisherIdentity: active.primaryMediaPublisherIdentity }
    )
    if (presence) {
      broadcasterConnected = presence.broadcasterConnected
      hostConnected = presence.hostConnected
      primaryMediaPublisherConnected = presence.primaryMediaPublisherConnected
      viewerCount = presence.viewerCount
    }
  }

  return Response.json({
    live,
    publicLive,
    visibility: active.visibility,
    broadcastSessionId: active.id,
    broadcasterUserId: active.broadcasterUserId,
    broadcasterDisplayName: active.broadcasterDisplayName,
    startedAt: active.startedAt,
    voiceMode: active.voiceMode,
    videoSource: active.videoSource,
    broadcastSource: active.broadcastSource,
    primaryMediaPublisherIdentity: active.primaryMediaPublisherIdentity,
    livekitIngressId: active.livekitIngressId,
    ingressStatusSnapshot: active.ingressStatusSnapshot,
    viewerCount,
    isBroadcaster,
    broadcasterConnected,
    hostConnected,
    primaryMediaPublisherConnected,
    alreadyLiveElsewhere:
      isBroadcaster && broadcasterConnected === true ? true : undefined,
  })
}
