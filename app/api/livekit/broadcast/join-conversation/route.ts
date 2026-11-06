import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { setLiveKitBroadcastParticipantMic } from "@/lib/livekit/liveKitRoomService.ts"
import { mintLiveKitBroadcastConversationToken } from "@/lib/livekit/mintLiveKitBroadcastToken.ts"
import { getActiveTradeRoomBroadcast } from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import { resolveTradeRoomBroadcastViewerAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import { parseRoomIdBody } from "../_shared.ts"

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
    return Response.json({ error: "LiveKit is not configured." }, { status: 503 })
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

  const access = await resolveTradeRoomBroadcastViewerAccess(supabaseServiceRole, {
    userId: user.id,
    roomId: parsed.roomId,
  })
  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  const active = await getActiveTradeRoomBroadcast(supabaseServiceRole, parsed.roomId)
  if (!active) {
    return Response.json({ error: "No live stream is active." }, { status: 404 })
  }

  if (active.voiceMode !== "open_voice") {
    const { hasActiveBroadcastSpeakerGrant } = await import(
      "@/lib/livekit/tradeRoomBroadcastInteractiveState.ts"
    )
    const granted = await hasActiveBroadcastSpeakerGrant(
      supabaseServiceRole,
      active.id,
      user.id
    )
    if (!granted) {
      return Response.json(
        {
          error:
            "This stream is broadcast-only. Wait for a speaking invitation from the host.",
        },
        { status: 403 }
      )
    }
  }

  if (active.broadcasterUserId === user.id) {
    return Response.json(
      { error: "You are already the broadcaster." },
      { status: 400 }
    )
  }

  try {
    await setLiveKitBroadcastParticipantMic(parsed.roomId, user.id, true)
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return Response.json(
      { error: `Could not grant microphone access: ${message}` },
      { status: 503 }
    )
  }

  const session = await mintLiveKitBroadcastConversationToken(
    user.id,
    parsed.roomId,
    access.displayName
  )
  if (!session) {
    return Response.json({ error: "Could not mint conversation token." }, { status: 503 })
  }

  return Response.json({
    ...session,
    broadcastSessionId: active.id,
  })
}
