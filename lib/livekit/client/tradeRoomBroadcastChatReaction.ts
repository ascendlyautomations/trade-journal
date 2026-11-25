import { Room, RoomEvent, type RemoteParticipant } from "livekit-client"
import { normalizeMessageReaction } from "@/lib/messageReactionValidation.ts"

export const BROADCAST_CHAT_REACTION_TOPIC = "tt_broadcast_chat_reaction"

export const BROADCAST_CHAT_REACTION_MIN_INTERVAL_MS = 250

export type BroadcastChatReactionRow = {
  messageId: string
  userId: string
  emoji: string
  updatedAt: number
}

type ChatReactionPayload = {
  type: "chat_reaction"
  messageId: string
  userId: string
  emoji: string | null
  sentAt: number
}

let lastSentAt = 0

export function clearBroadcastChatReactionSendState(): void {
  lastSentAt = 0
}

export function reactionsForBroadcastChatMessage(
  reactions: BroadcastChatReactionRow[],
  messageId: string
): BroadcastChatReactionRow[] {
  return reactions.filter((row) => row.messageId === messageId)
}

/** One reaction per user per message; remove row when emoji cleared. */
export function applyBroadcastChatReactionEvent(
  reactions: BroadcastChatReactionRow[],
  event: { messageId: string; userId: string; emoji: string | null; updatedAt: number }
): BroadcastChatReactionRow[] {
  const withoutUser = reactions.filter(
    (row) => !(row.messageId === event.messageId && row.userId === event.userId)
  )
  const emoji = event.emoji ? normalizeMessageReaction(event.emoji) : null
  if (!emoji) return withoutUser
  return [
    ...withoutUser,
    {
      messageId: event.messageId,
      userId: event.userId,
      emoji,
      updatedAt: event.updatedAt,
    },
  ]
}

export function parseBroadcastChatReactionPayload(
  data: Uint8Array | ArrayBuffer,
  senderIdentity: string
): { messageId: string; userId: string; emoji: string | null; updatedAt: number } | null {
  try {
    const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : data
    const raw = JSON.parse(new TextDecoder().decode(bytes)) as ChatReactionPayload
    if (raw.type !== "chat_reaction") return null
    if (raw.userId !== senderIdentity) return null
    const messageId = raw.messageId?.trim()
    if (!messageId) return null
    const sentAt =
      typeof raw.sentAt === "number" && Number.isFinite(raw.sentAt)
        ? raw.sentAt
        : Date.now()
    const emojiRaw = raw.emoji
    if (emojiRaw == null || emojiRaw === "") {
      return { messageId, userId: raw.userId, emoji: null, updatedAt: sentAt }
    }
    const emoji = normalizeMessageReaction(emojiRaw)
    if (!emoji) return null
    return { messageId, userId: raw.userId, emoji, updatedAt: sentAt }
  } catch {
    return null
  }
}

export async function publishBroadcastChatReaction(
  room: Room,
  options: {
    messageId: string
    userId: string
    emoji: string | null
  }
): Promise<{ ok: true; sentAt: number } | { ok: false; error: string }> {
  const messageId = options.messageId.trim()
  if (!messageId) return { ok: false, error: "Invalid message." }

  const emoji =
    options.emoji != null ? normalizeMessageReaction(options.emoji) : null
  if (options.emoji != null && !emoji) {
    return { ok: false, error: "Pick a valid emoji." }
  }

  const now = Date.now()
  if (now - lastSentAt < BROADCAST_CHAT_REACTION_MIN_INTERVAL_MS) {
    return { ok: false, error: "Slow down — try again." }
  }
  lastSentAt = now

  const payload: ChatReactionPayload = {
    type: "chat_reaction",
    messageId,
    userId: options.userId,
    emoji,
    sentAt: now,
  }

  const data = new TextEncoder().encode(JSON.stringify(payload))
  try {
    await room.localParticipant.publishData(data, {
      reliable: true,
      topic: BROADCAST_CHAT_REACTION_TOPIC,
    })
    return { ok: true, sentAt: now }
  } catch {
    return { ok: false, error: "Could not update reaction." }
  }
}

export function registerBroadcastChatReactionHandlers(
  room: Room,
  onReaction: (event: {
    messageId: string
    userId: string
    emoji: string | null
    updatedAt: number
  }) => void
): () => void {
  const handler = (
    payload: Uint8Array,
    participant?: RemoteParticipant,
    _?: unknown,
    topic?: string
  ) => {
    if (topic !== BROADCAST_CHAT_REACTION_TOPIC) return
    const identity = participant?.identity ?? room.localParticipant.identity
    if (!identity) return
    const parsed = parseBroadcastChatReactionPayload(payload, identity)
    if (parsed) onReaction(parsed)
  }

  room.on(RoomEvent.DataReceived, handler)
  return () => room.off(RoomEvent.DataReceived, handler)
}

export function viewerReactionRowsForToggle(
  reactions: BroadcastChatReactionRow[],
  messageId: string,
  viewerUserId: string
): BroadcastChatReactionRow[] {
  return reactions.filter(
    (row) => row.messageId === messageId && row.userId === viewerUserId
  )
}