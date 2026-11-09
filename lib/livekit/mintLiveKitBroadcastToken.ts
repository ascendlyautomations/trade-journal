import { AccessToken, TrackSource } from "livekit-server-sdk"
import { readLiveKitServerConfig } from "./config.ts"
import { liveKitBroadcastRoomName } from "./liveKitRoomName.ts"

export type MintedLiveKitBroadcastSession = {
  token: string
  livekitUrl: string
  roomName: string
  role: "broadcaster" | "viewer" | "conversation"
  canPublish: boolean
  canSubscribe: boolean
  canPublishData: boolean
  expiresInSeconds: number
}

export async function mintLiveKitBroadcastViewerToken(
  userId: string,
  roomId: string,
  displayName: string | null
): Promise<MintedLiveKitBroadcastSession | null> {
  const config = readLiveKitServerConfig()
  if (!config) return null

  const roomName = liveKitBroadcastRoomName(roomId)
  const at = new AccessToken(config.apiKey, config.apiSecret, {
    identity: userId,
    name: displayName ?? undefined,
    ttl: config.tokenTtlSeconds,
  })

  at.addGrant({
    roomJoin: true,
    room: roomName,
    canPublish: false,
    canSubscribe: true,
    canPublishData: true,
    canPublishSources: [],
  })

  const token = await at.toJwt()

  return {
    token,
    livekitUrl: config.livekitUrl,
    roomName,
    role: "viewer",
    canPublish: false,
    canSubscribe: true,
    canPublishData: true,
    expiresInSeconds: config.tokenTtlSeconds,
  }
}

export async function mintLiveKitBroadcastConversationToken(
  userId: string,
  roomId: string,
  displayName: string | null
): Promise<MintedLiveKitBroadcastSession | null> {
  const config = readLiveKitServerConfig()
  if (!config) return null

  const roomName = liveKitBroadcastRoomName(roomId)
  const at = new AccessToken(config.apiKey, config.apiSecret, {
    identity: userId,
    name: displayName ?? undefined,
    ttl: config.tokenTtlSeconds,
  })

  at.addGrant({
    roomJoin: true,
    room: roomName,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
    canPublishSources: [TrackSource.MICROPHONE],
  })

  const token = await at.toJwt()

  return {
    token,
    livekitUrl: config.livekitUrl,
    roomName,
    role: "conversation",
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
    expiresInSeconds: config.tokenTtlSeconds,
  }
}

export async function mintLiveKitBroadcastPublisherToken(
  userId: string,
  roomId: string,
  displayName: string | null
): Promise<MintedLiveKitBroadcastSession | null> {
  const config = readLiveKitServerConfig()
  if (!config) return null

  const roomName = liveKitBroadcastRoomName(roomId)
  const at = new AccessToken(config.apiKey, config.apiSecret, {
    identity: userId,
    name: displayName ?? undefined,
    ttl: config.tokenTtlSeconds,
  })

  at.addGrant({
    roomJoin: true,
    room: roomName,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
    canPublishSources: [
      TrackSource.SCREEN_SHARE,
      TrackSource.CAMERA,
      TrackSource.MICROPHONE,
    ],
  })

  const token = await at.toJwt()

  return {
    token,
    livekitUrl: config.livekitUrl,
    roomName,
    role: "broadcaster",
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
    expiresInSeconds: config.tokenTtlSeconds,
  }
}

/**
 * OBS broadcast host: subscribe + data + mic only — program video/audio from Ingress.
 */
export async function mintLiveKitBroadcastObsHostToken(
  userId: string,
  roomId: string,
  displayName: string | null
): Promise<MintedLiveKitBroadcastSession | null> {
  const config = readLiveKitServerConfig()
  if (!config) return null

  const roomName = liveKitBroadcastRoomName(roomId)
  const at = new AccessToken(config.apiKey, config.apiSecret, {
    identity: userId,
    name: displayName ?? undefined,
    ttl: config.tokenTtlSeconds,
  })

  at.addGrant({
    roomJoin: true,
    room: roomName,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
    canPublishSources: [TrackSource.MICROPHONE],
  })

  const token = await at.toJwt()

  return {
    token,
    livekitUrl: config.livekitUrl,
    roomName,
    role: "broadcaster",
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
    expiresInSeconds: config.tokenTtlSeconds,
  }
}
