import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import {
  mintLiveKitBroadcastObsHostToken,
  mintLiveKitBroadcastPublisherToken,
} from "@/lib/livekit/mintLiveKitBroadcastToken.ts"
import { claimTradeRoomBroadcastSession } from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import { resolveTradeRoomBroadcastControlAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit.ts"
import { parseStartBody } from "../_shared.ts"
import { after } from "next/server"
import { notifyTradeRoomMembersBroadcastLive } from "@/lib/server/notifications/handlers/tradeRoomBroadcastLiveNotify.ts"

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

  const parsed = parseStartBody(body)
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

  const claim = await claimTradeRoomBroadcastSession(supabaseServiceRole, {
    roomId: parsed.roomId,
    broadcasterUserId: user.id,
    voiceMode: parsed.voiceMode,
    videoSource: parsed.videoSource,
  })

  if (!claim.ok) {
    return Response.json({ error: claim.error }, { status: claim.status })
  }

  const session =
    parsed.videoSource === "obs"
      ? await mintLiveKitBroadcastObsHostToken(
          user.id,
          parsed.roomId,
          access.displayName
        )
      : await mintLiveKitBroadcastPublisherToken(
          user.id,
          parsed.roomId,
          access.displayName
        )

  if (!session) {
    return Response.json(
      { error: "Could not mint LiveKit broadcast token." },
      { status: 503 }
    )
  }

  if (parsed.videoSource !== "obs") {
    after(() => {
      void notifyTradeRoomMembersBroadcastLive({
        roomId: parsed.roomId,
        broadcasterUserId: user.id,
        broadcastSessionId: claim.session.id,
      })
    })
  }

  return Response.json({
    ...session,
    broadcastSessionId: claim.session.id,
    broadcasterUserId: claim.session.broadcasterUserId,
    broadcasterDisplayName: claim.session.broadcasterDisplayName,
    startedAt: claim.session.startedAt,
    voiceMode: claim.session.voiceMode,
    videoSource: claim.session.videoSource,
    broadcastSource: claim.session.broadcastSource,
    primaryMediaPublisherIdentity: claim.session.primaryMediaPublisherIdentity,
    visibility: claim.session.visibility,
    publicLive: claim.session.visibility === "public",
  })
}
