import { Room, RoomEvent, type RemoteParticipant } from "livekit-client"
import { normalizeBroadcastChatAvatarUrl } from "./tradeRoomBroadcastChatProfiles.ts"

export const BROADCAST_CHAT_TOPIC = "tt_broadcast_chat"
export const BROADCAST_CHAT_MAX_LENGTH = 500
export const BROADCAST_CHAT_MAX_MESSAGES = 200
export const BROADCAST_CHAT_MIN_INTERVAL_MS = 400

export type BroadcastChatMessage = {
  id: string
  userId: string
  displayName: string
  avatarUrl: string | null
  text: string
  sentAt: number
}

type ChatPayload = {
  type: "chat"
  userId: string
  displayName: string
  avatarUrl: string | null
  text: string
  sentAt: number
}

let lastSentAt = 0

export function clearBroadcastChatState(): void {
  lastSentAt = 0
}

export function parseBroadcastChatPayload(
  data: Uint8Array | ArrayBuffer,
  senderIdentity: string
): BroadcastChatMessage | null {
  try {
    const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : data
    const raw = JSON.parse(new TextDecoder().decode(bytes)) as ChatPayload
    if (raw.type !== "chat") return null
    if (raw.userId !== senderIdentity) return null
    const text = raw.text?.trim()
    if (!text || text.length > BROADCAST_CHAT_MAX_LENGTH) return null
    return {
      id: `${raw.userId}-${raw.sentAt}`,
      userId: raw.userId,
      displayName: raw.displayName?.trim() || "Member",
      avatarUrl: normalizeBroadcastChatAvatarUrl(raw.avatarUrl ?? null),
      text,
      sentAt: raw.sentAt,
    }
  } catch {
    return null
  }
}

export async function publishBroadcastChatMessage(
  room: Room,
  options: {
    userId: string
    displayName: string
    avatarUrl: string | null
    text: string
  }
): Promise<{ ok: true } | { ok: false; error: string }> {
  const trimmed = options.text.trim()
  if (!trimmed) return { ok: false, error: "Message is empty." }
  if (trimmed.length > BROADCAST_CHAT_MAX_LENGTH) {
    return { ok: false, error: "Message is too long." }
  }
  const now = Date.now()
  if (now - lastSentAt < BROADCAST_CHAT_MIN_INTERVAL_MS) {
    return { ok: false, error: "Slow down — you're sending messages too fast." }
  }
  lastSentAt = now

  const payload: ChatPayload = {
    type: "chat",
    userId: options.userId,
    displayName: options.displayName,
    avatarUrl: options.avatarUrl,
    text: trimmed,
    sentAt: now,
  }

  const data = new TextEncoder().encode(JSON.stringify(payload))
  try {
    await room.localParticipant.publishData(data, {
      reliable: true,
      topic: BROADCAST_CHAT_TOPIC,
    })
    return { ok: true }
  } catch {
    return { ok: false, error: "Could not send message." }
  }
}

export function registerBroadcastChatHandlers(
  room: Room,
  onMessage: (message: BroadcastChatMessage) => void
): () => void {
  const handler = (
    payload: Uint8Array,
    participant?: RemoteParticipant,
    _?: unknown,
    topic?: string
  ) => {
    if (topic !== BROADCAST_CHAT_TOPIC) return
    const identity = participant?.identity ?? room.localParticipant.identity
    if (!identity) return
    const msg = parseBroadcastChatPayload(payload, identity)
    if (msg) onMessage(msg)
  }

  room.on(RoomEvent.DataReceived, handler)
  return () => room.off(RoomEvent.DataReceived, handler)
}

export function trimBroadcastChatMessages(
  messages: BroadcastChatMessage[]
): BroadcastChatMessage[] {
  if (messages.length <= BROADCAST_CHAT_MAX_MESSAGES) return messages
  return messages.slice(messages.length - BROADCAST_CHAT_MAX_MESSAGES)
}
