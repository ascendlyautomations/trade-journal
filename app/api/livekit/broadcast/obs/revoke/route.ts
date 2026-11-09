import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { deleteLiveKitIngress } from "@/lib/livekit/liveKitIngressService.ts"
import { resolveTradeRoomBroadcastControlAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import {
  clearObsIngressMetadata,
  getActiveTradeRoomBroadcast,
} from "@/lib/livekit/tradeRoomBroadcastSession.ts"
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
    return Response.json({ ok: true, revoked: false })
  }

  if (active.broadcasterUserId !== user.id) {
    return Response.json(
      { error: "Only the authorized broadcaster can revoke OBS ingress." },
      { status: 403 }
    )
  }

  const ingressId = active.livekitIngressId?.trim() || ""
  if (ingressId) {
    await deleteLiveKitIngress(ingressId)
  }

  const cleared = await clearObsIngressMetadata(supabaseServiceRole, {
    roomId: parsed.roomId,
    sessionId: parsed.sessionId,
    broadcasterUserId: user.id,
  })

  if (!cleared.ok) {
    return Response.json({ error: cleared.error }, { status: cleared.status })
  }

  return Response.json({ ok: true, revoked: true })
}
