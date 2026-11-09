import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import {
  getActiveTradeRoomBroadcast,
} from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import { resolveTradeRoomBroadcastControlAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit.ts"
import { parseRoomIdBody } from "../_shared.ts"
import { after } from "next/server"
import { notifyTradeRoomMembersBroadcastLive } from "@/lib/server/notifications/handlers/tradeRoomBroadcastLiveNotify.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/**
 * OBS Stage 2: transition a preparing session to public discoverable live (notifications once).
 */
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

  const parsed = parseRoomIdBody(body)
  if (!parsed) {
    return Response.json({ error: "roomId is required." }, { status: 400 })
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
    { activeScope: "any", skipRecoverStale: true }
  )

  if (!active || active.broadcasterUserId !== user.id) {
    return Response.json(
      { error: "No preparing broadcast session found for this room." },
      { status: 404 }
    )
  }

  if (active.videoSource !== "obs") {
    return Response.json(
      { error: "This session is not an OBS broadcast." },
      { status: 400 }
    )
  }

  if (active.visibility === "public") {
    return Response.json({
      ok: true,
      broadcastSessionId: active.id,
      alreadyPublic: true,
    })
  }

  const { getLiveKitBroadcastRoomPresence } = await import(
    "@/lib/livekit/liveKitRoomService.ts"
  )
  const { primaryMediaPublisherIdentityForBroadcastSession } = await import(
    "@/lib/livekit/tradeRoomBroadcastObsIdentity.ts"
  )

  const primaryId =
    active.primaryMediaPublisherIdentity?.trim() ||
    primaryMediaPublisherIdentityForBroadcastSession(active.id)

  const presence = await getLiveKitBroadcastRoomPresence(parsed.roomId, user.id, {
    primaryMediaPublisherIdentity: primaryId,
  })

  if (!presence?.primaryMediaPublisherConnected) {
    return Response.json(
      {
        error:
          "OBS is not publishing yet. Start streaming in OBS and wait for the preview before going live.",
      },
      { status: 409 }
    )
  }

  const { error: updErr, data: updated } = await supabaseServiceRole
    .from("room_live_broadcasts")
    .update({
      visibility: "public",
      go_live_notified_at: new Date().toISOString(),
    })
    .eq("id", active.id)
    .eq("room_id", parsed.roomId)
    .eq("broadcaster_user_id", user.id)
    .eq("visibility", "preparing")
    .is("go_live_notified_at", null)
    .is("ended_at", null)
    .select("id")
    .maybeSingle()

  if (updErr) {
    console.error("[livekit/broadcast/publish] update failed", updErr.message)
    return Response.json({ error: "Could not publish broadcast." }, { status: 500 })
  }

  if (!updated?.id) {
    const again = await getActiveTradeRoomBroadcast(
      supabaseServiceRole,
      parsed.roomId,
      { activeScope: "any", skipRecoverStale: true }
    )
    if (again?.visibility === "public" && again.id === active.id) {
      return Response.json({
        ok: true,
        broadcastSessionId: active.id,
        alreadyPublic: true,
      })
    }
    return Response.json(
      { error: "Could not publish — session may have ended." },
      { status: 409 }
    )
  }

  after(() => {
    void notifyTradeRoomMembersBroadcastLive({
      roomId: parsed.roomId,
      broadcasterUserId: user.id,
      broadcastSessionId: active.id,
    })
  })

  return Response.json({
    ok: true,
    broadcastSessionId: active.id,
    alreadyPublic: false,
  })
}
