import type {
  TradeRoomBroadcastVideoSource,
  TradeRoomBroadcastVoiceMode,
} from "../tradeRoomBroadcastVoiceMode.ts"
import type { BroadcastConversationJoinPayload } from "./tradeRoomBroadcastJoinConversation.ts"

/** Viewer accepts invite — validates invitation, grants mic server-side, returns conversation token payload. */
export async function fetchBroadcastAcceptSpeakInvitePayload(
  accessToken: string,
  invitationId: string
): Promise<BroadcastConversationJoinPayload> {
  const res = await fetch("/api/livekit/broadcast/invite/respond", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ invitationId, accept: true }),
  })
  const payload = (await res.json().catch(() => ({}))) as {
    error?: string
    token?: string
    livekitUrl?: string
    broadcastSessionId?: string
    broadcasterUserId?: string
    broadcasterDisplayName?: string | null
    startedAt?: string
    voiceMode?: TradeRoomBroadcastVoiceMode
    videoSource?: TradeRoomBroadcastVideoSource
    broadcastSource?: "browser" | "obs"
    primaryMediaPublisherIdentity?: string | null
  }
  if (!res.ok || !payload.token || !payload.livekitUrl || !payload.broadcastSessionId) {
    throw new Error(payload.error || "Could not accept speaking invitation.")
  }
  return {
    token: payload.token,
    livekitUrl: payload.livekitUrl,
    broadcastSessionId: payload.broadcastSessionId,
    broadcasterUserId: payload.broadcasterUserId ?? "",
    broadcasterDisplayName: payload.broadcasterDisplayName ?? null,
    startedAt: payload.startedAt ?? new Date().toISOString(),
    voiceMode: payload.voiceMode,
    videoSource: payload.videoSource,
    broadcastSource: payload.broadcastSource,
    primaryMediaPublisherIdentity: payload.primaryMediaPublisherIdentity,
  }
}

export async function declineBroadcastSpeakInvite(
  accessToken: string,
  invitationId: string
): Promise<void> {
  const res = await fetch("/api/livekit/broadcast/invite/respond", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ invitationId, accept: false }),
  })
  const payload = (await res.json().catch(() => ({}))) as { error?: string }
  if (!res.ok) {
    throw new Error(payload.error || "Could not decline invitation.")
  }
}
