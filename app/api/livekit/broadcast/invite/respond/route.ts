import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { acceptBroadcastSpeakInvitation } from "@/lib/livekit/tradeRoomBroadcastModeration.ts"
import {
  respondBroadcastSpeakInvitation,
  revokeBroadcastSpeaker,
} from "@/lib/livekit/tradeRoomBroadcastInteractiveState.ts"
import {
  muteLiveKitBroadcastParticipantMicrophone,
  setLiveKitBroadcastParticipantMic,
} from "@/lib/livekit/liveKitRoomService.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

function parseBody(
  raw: unknown
): { invitationId: string; accept: boolean } | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const invitationId = typeof b.invitationId === "string" ? b.invitationId.trim() : ""
  if (!invitationId || typeof b.accept !== "boolean") return null
  return { invitationId, accept: b.accept }
}

export async function POST(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json(
      { error: "Unauthorized", detail: authError?.code ?? null },
      { status: 401 }
    )
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json({ error: "Invalid JSON body." }, { status: 400 })
  }

  const parsed = parseBody(body)
  if (!parsed) {
    return Response.json({ error: "invitationId and accept are required." }, { status: 400 })
  }

  if (!parsed.accept) {
    const declined = await respondBroadcastSpeakInvitation(supabaseServiceRole, {
      invitationId: parsed.invitationId,
      userId: user.id,
      accept: false,
    })
    if (!declined.ok) {
      return Response.json({ error: declined.error }, { status: declined.status })
    }
    const revoked = await revokeBroadcastSpeaker(supabaseServiceRole, {
      sessionId: declined.sessionId,
      targetUserId: user.id,
    })
    if (!revoked.ok) {
      return Response.json({ error: revoked.error }, { status: revoked.status })
    }
    try {
      await setLiveKitBroadcastParticipantMic(declined.roomId, user.id, false)
      await muteLiveKitBroadcastParticipantMicrophone(declined.roomId, user.id, true)
    } catch {
      /* participant may not be in room */
    }
    return Response.json({
      ok: true,
      declined: true,
      broadcastSessionId: declined.sessionId,
      roomId: declined.roomId,
    })
  }

  const { data: profileRow } = await supabaseServiceRole
    .from("profiles")
    .select("username, name")
    .eq("id", user.id)
    .maybeSingle()

  const displayName =
    profileRow?.name?.trim() || profileRow?.username?.trim() || null

  const accepted = await acceptBroadcastSpeakInvitation(supabaseServiceRole, {
    userId: user.id,
    invitationId: parsed.invitationId,
    displayName,
  })

  if (!accepted.ok) {
    return Response.json({ error: accepted.error }, { status: accepted.status })
  }

  if (!accepted.token) {
    return Response.json({ error: "Could not mint speaker token." }, { status: 503 })
  }

  return Response.json({
    ok: true,
    token: accepted.token.token,
    livekitUrl: accepted.token.livekitUrl,
    broadcastSessionId: accepted.sessionId,
    roomId: accepted.roomId,
    broadcasterUserId: accepted.broadcasterUserId,
    broadcasterDisplayName: accepted.broadcasterDisplayName,
    startedAt: accepted.startedAt,
    voiceMode: accepted.voiceMode,
    videoSource: accepted.videoSource,
    broadcastSource: accepted.broadcastSource,
    primaryMediaPublisherIdentity: accepted.primaryMediaPublisherIdentity,
    canPublish: accepted.token.canPublish,
    role: accepted.token.role,
  })
}
