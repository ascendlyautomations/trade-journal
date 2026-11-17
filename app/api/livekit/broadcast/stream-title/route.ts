import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { resolveTradeRoomBroadcastControlAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import { updateTradeRoomBroadcastStreamTitle } from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit.ts"
import { parseStreamTitleBody } from "../_shared.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/** Host updates stream title on an active session (no stream restart). */
export async function PATCH(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json(
      { error: "Unauthorized", detail: authError?.code ?? null },
      { status: 401 }
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

  const parsed = parseStreamTitleBody(body)
  if (!parsed) {
    return Response.json(
      { error: "roomId and sessionId are required." },
      { status: 400 }
    )
  }
  if ("error" in parsed) {
    return Response.json({ error: parsed.error }, { status: 400 })
  }

  const access = await resolveTradeRoomBroadcastControlAccess(supabaseServiceRole, {
    userId: user.id,
    roomId: parsed.roomId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  const result = await updateTradeRoomBroadcastStreamTitle(supabaseServiceRole, {
    roomId: parsed.roomId,
    sessionId: parsed.sessionId,
    broadcasterUserId: user.id,
    streamTitle: parsed.streamTitle,
  })

  if (!result.ok) {
    return Response.json({ error: result.error }, { status: result.status })
  }

  return Response.json({ ok: true, streamTitle: result.streamTitle })
}
