import { AccessToken, TrackSource } from "livekit-server-sdk"
import { readLiveKitServerConfig } from "./config.ts"
import { liveKitRoomName } from "./liveKitRoomName.ts"
import type { TradeRoomLiveVoiceAccess } from "./tradeRoomLiveVoiceAccess.ts"

export type MintedLiveKitSession = {
  token: string
  livekitUrl: string
  roomName: string
  mode: "open" | "stage"
  role: "listener" | "speaker" | "moderator"
  canPublish: boolean
  expiresInSeconds: number
}

export async function mintLiveKitVoiceToken(
  userId: string,
  access: Extract<TradeRoomLiveVoiceAccess, { ok: true }>
): Promise<MintedLiveKitSession | null> {
  const config = readLiveKitServerConfig()
  if (!config) return null

  const roomName = liveKitRoomName(access.roomId)
  const at = new AccessToken(config.apiKey, config.apiSecret, {
    identity: userId,
    name: access.displayName ?? undefined,
    ttl: config.tokenTtlSeconds,
  })

  at.addGrant({
    roomJoin: true,
    room: roomName,
    canPublish: access.canPublish,
    canSubscribe: access.canSubscribe,
    canPublishData: true,
    canPublishSources: access.canPublish ? [TrackSource.MICROPHONE] : [],
  })

  const token = await at.toJwt()

  return {
    token,
    livekitUrl: config.livekitUrl,
    roomName,
    mode: access.liveKind === "voice_open" ? "open" : "stage",
    role: access.role,
    canPublish: access.canPublish,
    expiresInSeconds: config.tokenTtlSeconds,
  }
}
