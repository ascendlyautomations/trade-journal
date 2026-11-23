import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  TRADE_ROOM_BROADCAST_DURATION_END_REASON,
  isBroadcastPastExpiresAt,
} from "./tradeRoomBroadcastDurationLimit.ts"
import {
  endTradeRoomBroadcastSession,
  type ActiveTradeRoomBroadcast,
} from "./tradeRoomBroadcastSession.ts"
import { setBroadcasterBroadcastCooldown } from "./tradeRoomBroadcastBroadcasterCooldown.ts"
import {
  deleteLiveKitBroadcastRoomIfEmpty,
  evictBroadcastRoomParticipants,
} from "./tradeRoomBroadcastReconcile.ts"

type DueRow = {
  id: string
  room_id: string
  broadcaster_user_id: string
  expires_at: string
}

function broadcastsTable(admin: SupabaseClient<Database>) {
  return admin.from("room_live_broadcasts")
}

export async function listDueBroadcastDurationExpirations(
  admin: SupabaseClient<Database>,
  options: { roomId?: string; sessionId?: string; limit?: number } = {}
): Promise<DueRow[]> {
  const nowIso = new Date().toISOString()
  const limit = Math.min(Math.max(options.limit ?? 25, 1), 50)

  let query = broadcastsTable(admin)
    .select("id, room_id, broadcaster_user_id, expires_at")
    .is("ended_at", null)
    .not("expires_at", "is", null)
    .lte("expires_at", nowIso)
    .order("expires_at", { ascending: true })
    .limit(limit)

  if (options.roomId) {
    query = query.eq("room_id", options.roomId)
  }
  if (options.sessionId) {
    query = query.eq("id", options.sessionId)
  }

  const { data, error } = await query
  if (error) {
    console.error("[livekit/broadcast] list due duration expirations failed", error.message)
    return []
  }
  return (data ?? []) as DueRow[]
}

export async function endBroadcastIfPastExpiresAt(
  admin: SupabaseClient<Database>,
  active: Pick<
    ActiveTradeRoomBroadcast,
  "id" | "roomId" | "broadcasterUserId" | "expiresAt"
  >
): Promise<boolean> {
  if (!isBroadcastPastExpiresAt(active.expiresAt ?? null)) {
    return false
  }
  return endExpiredBroadcastSession(admin, {
    roomId: active.roomId,
    sessionId: active.id,
    broadcasterUserId: active.broadcasterUserId,
  })
}

async function endExpiredBroadcastSession(
  admin: SupabaseClient<Database>,
  row: Pick<DueRow, "id" | "room_id" | "broadcaster_user_id">
): Promise<boolean> {
  const ended = await endTradeRoomBroadcastSession(admin, {
    roomId: row.room_id,
    sessionId: row.id,
    actorUserId: row.broadcaster_user_id,
    reason: TRADE_ROOM_BROADCAST_DURATION_END_REASON,
  })
  if (!ended.ok) {
    return false
  }

  await setBroadcasterBroadcastCooldown(admin, row.broadcaster_user_id)
  await evictBroadcastRoomParticipants(row.room_id)
  await deleteLiveKitBroadcastRoomIfEmpty(row.room_id)
  return true
}

export async function processBroadcastDurationExpirations(
  admin: SupabaseClient<Database>,
  options: { roomId?: string; sessionId?: string; limit?: number } = {}
): Promise<{ examined: number; ended: number }> {
  const due = await listDueBroadcastDurationExpirations(admin, options)
  let ended = 0
  for (const row of due) {
    const ok = await endExpiredBroadcastSession(admin, row)
    if (ok) ended += 1
  }
  return { examined: due.length, ended }
}