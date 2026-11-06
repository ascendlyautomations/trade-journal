import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  endTradeRoomBroadcastSession,
  getActiveTradeRoomBroadcast,
} from "./tradeRoomBroadcastSession.ts"
import {
  deleteLiveKitBroadcastRoom,
  isBroadcasterConnectedInBroadcastRoom,
} from "./liveKitRoomService.ts"
import { liveKitBroadcastRoomName } from "./liveKitRoomName.ts"
import { getLiveKitRoomServiceClient } from "./liveKitRoomService.ts"

export type BroadcastReconcileResult =
  | { state: "none" }
  | {
      state: "already_live"
      sessionId: string
      broadcasterConnected: boolean
      isOwner: boolean
    }
  | { state: "ended_abandoned"; sessionId: string }
  | { state: "ended_by_reconcile"; sessionId: string }

export async function reconcileTradeRoomBroadcastSession(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    viewerUserId: string
    endIfBroadcasterAbsent?: boolean
  }
): Promise<BroadcastReconcileResult> {
  const active = await getActiveTradeRoomBroadcast(admin, options.roomId)
  if (!active) {
    return { state: "none" }
  }

  const isOwner = active.broadcasterUserId === options.viewerUserId
  const broadcasterConnected = await isBroadcasterConnectedInBroadcastRoom(
    options.roomId,
    active.broadcasterUserId
  )

  if (broadcasterConnected) {
    return {
      state: "already_live",
      sessionId: active.id,
      broadcasterConnected: true,
      isOwner,
    }
  }

  if (!options.endIfBroadcasterAbsent) {
    return {
      state: "already_live",
      sessionId: active.id,
      broadcasterConnected: false,
      isOwner,
    }
  }

  if (!isOwner) {
    return {
      state: "already_live",
      sessionId: active.id,
      broadcasterConnected: false,
      isOwner: false,
    }
  }

  const end = await endTradeRoomBroadcastSession(admin, {
    roomId: options.roomId,
    sessionId: active.id,
    actorUserId: options.viewerUserId,
    reason: "abandoned_reconcile",
  })

  if (!end.ok) {
    return {
      state: "already_live",
      sessionId: active.id,
      broadcasterConnected: false,
      isOwner: true,
    }
  }

  await evictBroadcastRoomParticipants(options.roomId)
  await deleteLiveKitBroadcastRoomIfEmpty(options.roomId)

  return { state: "ended_abandoned", sessionId: active.id }
}

export async function evictBroadcastRoomParticipants(
  roomId: string,
  exceptIdentity?: string
): Promise<void> {
  const client = getLiveKitRoomServiceClient()
  if (!client) return
  const roomName = liveKitBroadcastRoomName(roomId)
  try {
    const participants = await client.listParticipants(roomName)
    for (const p of participants) {
      const identity = p.identity
      if (!identity || identity === exceptIdentity) continue
      try {
        await client.removeParticipant(roomName, identity)
      } catch {
        // already disconnected
      }
    }
  } catch {
    // room may not exist
  }
}

export async function deleteLiveKitBroadcastRoomIfEmpty(roomId: string): Promise<void> {
  const client = getLiveKitRoomServiceClient()
  if (!client) return
  try {
    const participants = await client.listParticipants(
      liveKitBroadcastRoomName(roomId)
    )
    if (participants.length === 0) {
      await deleteLiveKitBroadcastRoom(roomId)
    }
  } catch {
    // ignore
  }
}
