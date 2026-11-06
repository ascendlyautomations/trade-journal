import { LIVEKIT_TRADE_ROOM_BROADCAST_SEGMENT } from "./tradeRoomSharedBroadcast.ts"
import { LIVEKIT_TRADE_ROOM_VOICE_SEGMENT } from "./tradeRoomSharedLiveVoice.ts"

const PREFIX = "tt/"

/** Stable LiveKit room name for a Trade Room shared voice channel. */
export function liveKitRoomName(roomId: string): string {
  const room = roomId.trim()
  if (!room) {
    throw new Error("roomId is required for LiveKit room name.")
  }
  return `${PREFIX}${room}/${LIVEKIT_TRADE_ROOM_VOICE_SEGMENT}`
}

/** Stable LiveKit room name for Trade Room screen-share broadcast. */
export function liveKitBroadcastRoomName(roomId: string): string {
  const room = roomId.trim()
  if (!room) {
    throw new Error("roomId is required for LiveKit broadcast room name.")
  }
  return `${PREFIX}${room}/${LIVEKIT_TRADE_ROOM_BROADCAST_SEGMENT}`
}

export function parseLiveKitRoomName(name: string): { roomId: string } | null {
  const trimmed = name.trim()
  if (!trimmed.startsWith(PREFIX)) return null
  const rest = trimmed.slice(PREFIX.length)
  const slash = rest.indexOf("/")
  if (slash <= 0) return null
  const roomId = rest.slice(0, slash)
  const segment = rest.slice(slash + 1)
  if (!roomId || !segment) return null
  if (segment !== LIVEKIT_TRADE_ROOM_VOICE_SEGMENT) {
    return null
  }
  return { roomId }
}

export function parseLiveKitBroadcastRoomName(name: string): { roomId: string } | null {
  const trimmed = name.trim()
  if (!trimmed.startsWith(PREFIX)) return null
  const rest = trimmed.slice(PREFIX.length)
  const slash = rest.indexOf("/")
  if (slash <= 0) return null
  const roomId = rest.slice(0, slash)
  const segment = rest.slice(slash + 1)
  if (!roomId || segment !== LIVEKIT_TRADE_ROOM_BROADCAST_SEGMENT) {
    return null
  }
  return { roomId }
}

/** Pre–shared-voice section-scoped names (disconnect cleanup only). */
export function legacySectionLiveKitRoomName(
  roomId: string,
  sectionId: string
): string {
  const room = roomId.trim()
  const section = sectionId.trim()
  return `${PREFIX}${room}/${section}`
}

export function parseLegacySectionLiveKitRoomName(name: string): {
  roomId: string
  sectionId: string
} | null {
  const trimmed = name.trim()
  if (!trimmed.startsWith(PREFIX)) return null
  const rest = trimmed.slice(PREFIX.length)
  const slash = rest.indexOf("/")
  if (slash <= 0) return null
  const roomId = rest.slice(0, slash)
  const sectionId = rest.slice(slash + 1)
  if (!roomId || !sectionId || sectionId === LIVEKIT_TRADE_ROOM_VOICE_SEGMENT) {
    return null
  }
  return { roomId, sectionId }
}
