import { Room, RoomEvent, type RemoteParticipant } from "livekit-client"

/** Matches native iOS `tt_broadcast_hand` / `LiveVoiceHandPayload`. */
export const BROADCAST_HAND_TOPIC = "tt_broadcast_hand"

export type BroadcastHandState = {
  identity: string
  raised: boolean
}

type HandPayload = {
  type: "hand_state"
  identity: string
  raised: boolean
}

export function parseBroadcastHandPayload(
  data: Uint8Array | ArrayBuffer,
  senderIdentity: string
): BroadcastHandState | null {
  try {
    const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : data
    const raw = JSON.parse(new TextDecoder().decode(bytes)) as HandPayload
    if (raw.type !== "hand_state") return null
    if (raw.identity !== senderIdentity) return null
    return { identity: raw.identity, raised: Boolean(raw.raised) }
  } catch {
    return null
  }
}

export async function publishBroadcastHandState(
  room: Room,
  identity: string,
  raised: boolean
): Promise<{ ok: true } | { ok: false; error: string }> {
  const payload: HandPayload = {
    type: "hand_state",
    identity,
    raised,
  }
  const data = new TextEncoder().encode(JSON.stringify(payload))
  try {
    await room.localParticipant.publishData(data, {
      reliable: true,
      topic: BROADCAST_HAND_TOPIC,
    })
    return { ok: true }
  } catch {
    return { ok: false, error: "Could not update raise hand." }
  }
}

export function registerBroadcastHandHandlers(
  room: Room,
  onHand: (state: BroadcastHandState) => void
): () => void {
  const handler = (
    payload: Uint8Array,
    participant?: RemoteParticipant,
    _?: unknown,
    topic?: string
  ) => {
    if (topic !== BROADCAST_HAND_TOPIC) return
    const identity = participant?.identity ?? room.localParticipant.identity
    if (!identity) return
    const state = parseBroadcastHandPayload(payload, identity)
    if (state) onHand(state)
  }

  room.on(RoomEvent.DataReceived, handler)
  return () => room.off(RoomEvent.DataReceived, handler)
}
