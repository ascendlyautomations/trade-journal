import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import {
  createObsRtmpIngress,
  deleteLiveKitIngress,
  ingressStatusLabel,
} from "@/lib/livekit/liveKitIngressService.ts"
import { resolveTradeRoomBroadcastControlAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import {
  attachObsRtmpIngressToActiveSession,
  getActiveTradeRoomBroadcast,
} from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import { primaryMediaPublisherIdentityForBroadcastSession } from "@/lib/livekit/tradeRoomBroadcastObsIdentity.ts"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit.ts"
import { parseObsSessionBody } from "../_shared.ts"

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

  const rate = await consumeDurableUserRateLimit(
    user.id,
    "livekit_broadcast_control"
  )
  if (!rate.allowed) {
    return rateLimitExceededResponse(rate.retryAfterSec)
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json({ error: "Invalid JSON body." }, { status: 400 })
  }

  const parsed = parseObsSessionBody(body)
  if (!parsed) {
    return Response.json(
      { error: "roomId and sessionId are required." },
      { status: 400 }
    )
  }

  const access = await resolveTradeRoomBroadcastControlAccess(supabaseServiceRole, {
    userId: user.id,
    roomId: parsed.roomId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  const active = await getActiveTradeRoomBroadcast(
    supabaseServiceRole,
    parsed.roomId,
    { skipRecoverStale: true, activeScope: "any" }
  )

  if (!active || active.id !== parsed.sessionId) {
    return Response.json(
      { error: "No active broadcast session found for this room." },
      { status: 404 }
    )
  }

  if (active.broadcasterUserId !== user.id) {
    return Response.json(
      { error: "Only the authorized broadcaster can create OBS credentials." },
      { status: 403 }
    )
  }

  if (active.broadcastSource === "obs" && active.livekitIngressId?.trim()) {
    return Response.json(
      {
        error:
          "This session already has OBS ingress. Revoke it before creating new credentials.",
      },
      { status: 409 }
    )
  }

  const primaryIdentity = primaryMediaPublisherIdentityForBroadcastSession(active.id)
  const displayName = access.displayName?.trim() || "Live"

  const created = await createObsRtmpIngress({
    roomId: parsed.roomId,
    participantIdentity: primaryIdentity,
    participantDisplayName: displayName,
  })

  if (!created.ok) {
    const isUnsupported =
      /not available|Ingress is not/i.test(created.error) ||
      created.error.includes("Enable Ingress")
    return Response.json(
      { error: created.error },
      { status: isUnsupported ? 503 : 502 }
    )
  }

  const ingressId = created.info.ingressId?.trim() || ""
  if (!ingressId) {
    return Response.json(
      { error: "LiveKit did not return an ingress id." },
      { status: 502 }
    )
  }

  const attach = await attachObsRtmpIngressToActiveSession(supabaseServiceRole, {
    roomId: parsed.roomId,
    broadcasterUserId: user.id,
    sessionId: active.id,
    livekitIngressId: ingressId,
    primaryMediaPublisherIdentity: primaryIdentity,
    ingressStatusLabel: ingressStatusLabel(created.info),
  })

  if (!attach.ok) {
    await deleteLiveKitIngress(ingressId)
    return Response.json({ error: attach.error }, { status: attach.status })
  }

  const rtmpUrl = created.info.url?.trim() || ""
  const streamKey = created.info.streamKey?.trim() || ""
  if (!rtmpUrl || !streamKey) {
    await deleteLiveKitIngress(ingressId)
    return Response.json(
      { error: "LiveKit ingress response missing RTMP URL or stream key." },
      { status: 502 }
    )
  }

  return Response.json({
    broadcastSessionId: active.id,
    broadcastSource: "obs" as const,
    primaryMediaPublisherIdentity: primaryIdentity,
    livekitIngressId: ingressId,
    ingressStatusSnapshot: ingressStatusLabel(created.info),
    rtmpUrl,
    streamKey,
  })
}
