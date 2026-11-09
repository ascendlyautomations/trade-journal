import type {
  TradeRoomBroadcastVideoSource,
  TradeRoomBroadcastVoiceMode,
} from "../tradeRoomBroadcastVoiceMode.ts"

export type BroadcastConversationJoinPayload = {
  token: string
  livekitUrl: string
  broadcastSessionId: string
  broadcasterUserId: string
  broadcasterDisplayName: string | null
  startedAt: string
  voiceMode?: TradeRoomBroadcastVoiceMode
  videoSource?: TradeRoomBroadcastVideoSource
  broadcastSource?: "browser" | "obs"
  primaryMediaPublisherIdentity?: string | null
}

export async function fetchBroadcastConversationJoinPayload(
  accessToken: string,
  roomId: string
): Promise<BroadcastConversationJoinPayload> {
  const res = await fetch("/api/livekit/broadcast/join-conversation", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ roomId }),
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
    throw new Error(payload.error || "Could not join as a speaker.")
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
