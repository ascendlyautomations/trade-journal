import { Room, RoomEvent, type RemoteParticipant } from "livekit-client"
import { normalizeBroadcastChatAvatarUrl } from "./tradeRoomBroadcastChatProfiles.ts"

export const BROADCAST_CHAT_TOPIC = "tt_broadcast_chat"
export const BROADCAST_CHAT_MAX_LENGTH = 500
export const BROADCAST_CHAT_MAX_MESSAGES = 200
export const BROADCAST_CHAT_MIN_INTERVAL_MS = 400

export type BroadcastChatReplyReference = {
  messageId: string
  userId: string
  displayName: string
  textPreview: string
}

export type BroadcastChatMessage = {
  id: string
  userId: string
  displayName: string
  avatarUrl: string | null
  text: string
  sentAt: number
  imageUrl?: string | null
  tradeId?: string | null
  replyTo?: BroadcastChatReplyReference | null
}

type ChatPayload = {
  type: "chat"
  userId: string
  displayName: string
  avatarUrl: string | null
  text: string
  sentAt: number
  imageUrl?: string
  tradeId?: string
  replyToMessageId?: string
  replyToUserId?: string
  replyToDisplayName?: string
  replyToTextPreview?: string
}

const REPLY_PREVIEW_MAX_LENGTH = 100

function previewReplyText(text: string): string {
  const trimmed = text.trim()
  if (trimmed.length <= REPLY_PREVIEW_MAX_LENGTH) return trimmed
  return `${trimmed.slice(0, REPLY_PREVIEW_MAX_LENGTH)}…`
}

function decodeReplyReference(raw: ChatPayload): BroadcastChatReplyReference | null {
  const messageId = raw.replyToMessageId?.trim()
  if (!messageId) return null
  const userId = raw.replyToUserId?.trim()
  const displayName = raw.replyToDisplayName?.trim()
  const textPreview = raw.replyToTextPreview?.trim()
  if (!userId || !displayName || !textPreview) return null
  if (textPreview.length > REPLY_PREVIEW_MAX_LENGTH + 4) return null
  return { messageId, userId, displayName, textPreview }
}

export function isAllowedBroadcastImageUrl(raw: string | undefined): string | null {
  if (!raw) return null
  const trimmed = raw.trim()
  if (!trimmed || trimmed.length > 2048) return null
  try {
    const url = new URL(trimmed)
    if (url.protocol !== "https:") return null
    if (!url.hostname) return null
    return trimmed
  } catch {
    return null
  }
}

export function sanitizeTradeId(raw: string | undefined): string | null {
  if (!raw) return null
  const trimmed = raw.trim()
  return trimmed.length > 0 ? trimmed : null
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
    const text = raw.text?.trim() ?? ""
    const imageUrl = isAllowedBroadcastImageUrl(raw.imageUrl)
    const tradeId = sanitizeTradeId(raw.tradeId)
    if (!text && !imageUrl && !tradeId) return null
    if (text.length > BROADCAST_CHAT_MAX_LENGTH) return null
    const replyTo = decodeReplyReference(raw)
    return {
      id: `${raw.userId}-${raw.sentAt}`,
      userId: raw.userId,
      displayName: raw.displayName?.trim() || "Member",
      avatarUrl: normalizeBroadcastChatAvatarUrl(raw.avatarUrl ?? null),
      text,
      sentAt: raw.sentAt,
      imageUrl,
      tradeId,
      replyTo,
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
    imageUrl?: string | null
    tradeId?: string | null
    replyTo?: BroadcastChatReplyReference | null
  }
): Promise<{ ok: true } | { ok: false; error: string }> {
  const trimmed = options.text.trim()
  const imageUrl = isAllowedBroadcastImageUrl(options.imageUrl ?? undefined)
  const tradeId = sanitizeTradeId(options.tradeId ?? undefined)
  if (!trimmed && !imageUrl && !tradeId) return { ok: false, error: "Message is empty." }
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
    ...(imageUrl ? { imageUrl } : {}),
    ...(tradeId ? { tradeId } : {}),
    ...(options.replyTo
      ? {
          replyToMessageId: options.replyTo.messageId,
          replyToUserId: options.replyTo.userId,
          replyToDisplayName: options.replyTo.displayName,
          replyToTextPreview: previewReplyText(options.replyTo.textPreview),
        }
      : {}),
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