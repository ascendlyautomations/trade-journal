import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import {
  evictBroadcastRoomParticipants,
  deleteLiveKitBroadcastRoomIfEmpty,
} from "@/lib/livekit/tradeRoomBroadcastReconcile.ts"
import { endTradeRoomBroadcastSession } from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import {
  resolveTradeRoomBroadcastControlAccess,
  resolveTradeRoomBroadcastViewerAccess,
} from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit.ts"
import { parseStopBody } from "../_shared.ts"

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

  const parsed = parseStopBody(body)
  if (!parsed) {
    return Response.json(
      { error: "roomId and sessionId are required." },
      { status: 400 }
    )
  }

  const viewer = await resolveTradeRoomBroadcastViewerAccess(supabaseServiceRole, {
    userId: user.id,
    roomId: parsed.roomId,
  })

  if (!viewer.ok) {
    return Response.json({ error: viewer.error }, { status: viewer.status })
  }

  const control = await resolveTradeRoomBroadcastControlAccess(
    supabaseServiceRole,
    { userId: user.id, roomId: parsed.roomId }
  )

  const end = await endTradeRoomBroadcastSession(supabaseServiceRole, {
    roomId: parsed.roomId,
    sessionId: parsed.sessionId,
    actorUserId: user.id,
    reason: "client_stop",
    allowModeratorForce: control.ok,
  })

  if (!end.ok) {
    return Response.json({ error: end.error }, { status: end.status })
  }

  await evictBroadcastRoomParticipants(parsed.roomId)
  await deleteLiveKitBroadcastRoomIfEmpty(parsed.roomId)

  return Response.json({ ok: true })
}
