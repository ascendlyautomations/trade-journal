import { Room, RoomEvent, type RemoteParticipant } from "livekit-client"
import { normalizeMessageReaction } from "@/lib/messageReactionValidation.ts"

export const BROADCAST_REACTION_TOPIC = "tt_broadcast_reaction"

/** Client-side anti-spam: min gap between sends; burst cap in a sliding window. */
export const BROADCAST_REACTION_MIN_INTERVAL_MS = 300
export const BROADCAST_REACTION_BURST_MAX = 12
export const BROADCAST_REACTION_BURST_WINDOW_MS = 8_000

export type BroadcastFloatingReaction = {
  id: string
  emoji: string
  userId: string
  sentAt: number
  /** 0–1 horizontal anchor over the video layer */
  originX: number
}

type ReactionPayload = {
  type: "reaction"
  userId: string
  emoji: string
  sentAt: number
  originX?: number
}

let lastSentAt = 0
const sentTimestamps: number[] = []

export function clearBroadcastReactionSendState(): void {
  lastSentAt = 0
  sentTimestamps.length = 0
}

export function parseBroadcastReactionPayload(
  data: Uint8Array | ArrayBuffer,
  senderIdentity: string
): BroadcastFloatingReaction | null {
  try {
    const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : data
    const raw = JSON.parse(new TextDecoder().decode(bytes)) as ReactionPayload
    if (raw.type !== "reaction") return null
    if (raw.userId !== senderIdentity) return null
    const emoji = normalizeMessageReaction(raw.emoji ?? "")
    if (!emoji) return null
    const sentAt =
      typeof raw.sentAt === "number" && Number.isFinite(raw.sentAt)
        ? raw.sentAt
        : Date.now()
    const originX =
      typeof raw.originX === "number" && raw.originX >= 0 && raw.originX <= 1
        ? raw.originX
        : Math.random() * 0.6 + 0.2
    return {
      id: `${raw.userId}-${sentAt}-${emoji}`,
      emoji,
      userId: raw.userId,
      sentAt,
      originX,
    }
  } catch {
    return null
  }
}

export async function publishBroadcastReaction(
  room: Room,
  options: { userId: string; emoji: string; originX?: number }
): Promise<{ ok: true } | { ok: false; error: string }> {
  const emoji = normalizeMessageReaction(options.emoji)
  if (!emoji) return { ok: false, error: "Pick a valid emoji." }

  const now = Date.now()
  if (now - lastSentAt < BROADCAST_REACTION_MIN_INTERVAL_MS) {
    return { ok: false, error: "Slow down — you're sending reactions too fast." }
  }

  while (sentTimestamps.length > 0 && now - sentTimestamps[0]! > BROADCAST_REACTION_BURST_WINDOW_MS) {
    sentTimestamps.shift()
  }
  if (sentTimestamps.length >= BROADCAST_REACTION_BURST_MAX) {
    return { ok: false, error: "Too many reactions — try again in a moment." }
  }

  const originX =
    options.originX != null && options.originX >= 0 && options.originX <= 1
      ? options.originX
      : Math.random() * 0.6 + 0.2

  const payload: ReactionPayload = {
    type: "reaction",
    userId: options.userId,
    emoji,
    sentAt: now,
    originX,
  }

  lastSentAt = now
  sentTimestamps.push(now)

  const data = new TextEncoder().encode(JSON.stringify(payload))
  try {
    await room.localParticipant.publishData(data, {
      reliable: false,
      topic: BROADCAST_REACTION_TOPIC,
    })
    return { ok: true }
  } catch {
    return { ok: false, error: "Could not send reaction." }
  }
}

export function registerBroadcastReactionHandlers(
  room: Room,
  onReaction: (reaction: BroadcastFloatingReaction) => void
): () => void {
  const handler = (
    payload: Uint8Array,
    participant?: RemoteParticipant,
    _?: unknown,
    topic?: string
  ) => {
    if (topic !== BROADCAST_REACTION_TOPIC) return
    const identity = participant?.identity ?? room.localParticipant.identity
    if (!identity) return
    const parsed = parseBroadcastReactionPayload(payload, identity)
    if (parsed) onReaction(parsed)
  }

  room.on(RoomEvent.DataReceived, handler)
  return () => room.off(RoomEvent.DataReceived, handler)
}