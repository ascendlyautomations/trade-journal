import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  endTradeRoomBroadcastIfActive,
  getActiveTradeRoomBroadcast,
} from "./tradeRoomBroadcastSession.ts"
import {
  deleteLiveKitBroadcastRoomIfEmpty,
  evictBroadcastRoomParticipants,
} from "./tradeRoomBroadcastReconcile.ts"
import { isBroadcasterConnectedInBroadcastRoom } from "./liveKitRoomService.ts"

/** Grace after LiveKit disconnect signals before ending the Supabase session. */
export const BROADCAST_DISCONNECT_GRACE_MS = 8_000

export const BROADCAST_DISCONNECT_CRON_MAX_LAG_MS = 60_000

function broadcastsTable(admin: SupabaseClient<Database>) {
  return admin.from("room_live_broadcasts")
}

export type BroadcastDisconnectDueRow = {
  id: string
  room_id: string
  broadcaster_user_id: string
  broadcaster_disconnect_check_at: string
  broadcaster_disconnect_reason: string | null
}

export async function scheduleBroadcasterDisconnectCheck(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
    reason: string
  }
): Promise<void> {
  const checkAt = new Date(Date.now() + BROADCAST_DISCONNECT_GRACE_MS).toISOString()
  const { error } = await broadcastsTable(admin)
    .update({
      broadcaster_disconnect_check_at: checkAt,
      broadcaster_disconnect_reason: options.reason.slice(0, 120),
      last_livekit_signal_at: new Date().toISOString(),
    })
    .eq("id", options.sessionId)
    .eq("room_id", options.roomId)
    .is("ended_at", null)

  if (error) {
    console.error("[livekit/broadcast] schedule disconnect check failed", error.message)
  }
}

export async function clearBroadcasterDisconnectCheck(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
  }
): Promise<void> {
  const { error } = await broadcastsTable(admin)
    .update({
      broadcaster_disconnect_check_at: null,
      broadcaster_disconnect_reason: null,
      last_livekit_signal_at: new Date().toISOString(),
    })
    .eq("id", options.sessionId)
    .eq("room_id", options.roomId)
    .is("ended_at", null)

  if (error) {
    console.error("[livekit/broadcast] clear disconnect check failed", error.message)
  }
}

export async function listDueBroadcasterDisconnectChecks(
  admin: SupabaseClient<Database>,
  options: { roomId?: string; sessionId?: string; limit?: number }
): Promise<BroadcastDisconnectDueRow[]> {
  const nowIso = new Date().toISOString()
  const limit = Math.min(Math.max(options.limit ?? 20, 1), 50)

  let query = broadcastsTable(admin)
    .select(
      "id, room_id, broadcaster_user_id, broadcaster_disconnect_check_at, broadcaster_disconnect_reason"
    )
    .is("ended_at", null)
    .not("broadcaster_disconnect_check_at", "is", null)
    .lte("broadcaster_disconnect_check_at", nowIso)
    .order("broadcaster_disconnect_check_at", { ascending: true })
    .limit(limit)

  if (options.roomId) {
    query = query.eq("room_id", options.roomId)
  }
  if (options.sessionId) {
    query = query.eq("id", options.sessionId)
  }

  const { data, error } = await query
  if (error) {
    console.error("[livekit/broadcast] list due disconnect checks failed", error.message)
    return []
  }
  return (data ?? []) as BroadcastDisconnectDueRow[]
}

export async function processBroadcasterDisconnectChecks(
  admin: SupabaseClient<Database>,
  options: { roomId?: string; sessionId?: string; limit?: number } = {}
): Promise<{ examined: number; ended: number; skipped: number; cleared: number }> {
  const due = await listDueBroadcasterDisconnectChecks(admin, options)
  let ended = 0
  let skipped = 0
  let cleared = 0

  for (const row of due) {
    const outcome = await processOneBroadcasterDisconnectCheck(admin, row)
    if (outcome === "ended") ended += 1
    else if (outcome === "cleared") cleared += 1
    else skipped += 1
  }

  return { examined: due.length, ended, skipped, cleared }
}

export type DisconnectCheckOutcome = "ended" | "cleared" | "skipped"

export type DisconnectCheckDecision =
  | { action: "wait" }
  | { action: "clear"; reason: "stale_session" | "reconnected" }
  | { action: "end"; reason: string }

export function decideBroadcasterDisconnectCheck(input: {
  nowMs: number
  checkAtMs: number
  rowSessionId: string
  activeSessionId: string | null
  broadcasterConnected: boolean
  pendingReason: string | null
}): DisconnectCheckDecision {
  if (input.checkAtMs > input.nowMs) {
    return { action: "wait" }
  }
  if (!input.activeSessionId || input.activeSessionId !== input.rowSessionId) {
    return { action: "clear", reason: "stale_session" }
  }
  if (input.broadcasterConnected) {
    return { action: "clear", reason: "reconnected" }
  }
  return {
    action: "end",
    reason: input.pendingReason?.trim() || "livekit_disconnect_check",
  }
}

export async function processOneBroadcasterDisconnectCheck(
  admin: SupabaseClient<Database>,
  row: BroadcastDisconnectDueRow
): Promise<DisconnectCheckOutcome> {
  const checkAtMs = new Date(row.broadcaster_disconnect_check_at).getTime()
  const active = await getActiveTradeRoomBroadcast(admin, row.room_id, {
    activeScope: "any",
  })
  const connected =
    active?.id === row.id
      ? await isBroadcasterConnectedInBroadcastRoom(
          row.room_id,
          row.broadcaster_user_id,
          active.primaryMediaPublisherIdentity
        )
      : false

  const decision = decideBroadcasterDisconnectCheck({
    nowMs: Date.now(),
    checkAtMs,
    rowSessionId: row.id,
    activeSessionId: active?.id ?? null,
    broadcasterConnected: connected,
    pendingReason: row.broadcaster_disconnect_reason,
  })

  if (decision.action === "wait") {
    return "skipped"
  }

  if (decision.action === "clear") {
    if (decision.reason === "reconnected") {
      await clearBroadcasterDisconnectCheck(admin, {
        roomId: row.room_id,
        sessionId: row.id,
      })
    } else {
      await clearDisconnectCheckFields(admin, row.id, row.room_id)
    }
    return "cleared"
  }

  const didEnd = await endTradeRoomBroadcastIfActive(admin, {
    roomId: row.room_id,
    sessionId: row.id,
    broadcasterUserId: row.broadcaster_user_id,
    reason: decision.reason,
  })

  await clearDisconnectCheckFields(admin, row.id, row.room_id)

  if (!didEnd) {
    return "skipped"
  }

  await evictBroadcastRoomParticipants(row.room_id)
  await deleteLiveKitBroadcastRoomIfEmpty(row.room_id)
  return "ended"
}

async function clearDisconnectCheckFields(
  admin: SupabaseClient<Database>,
  sessionId: string,
  roomId: string
): Promise<void> {
  await broadcastsTable(admin)
    .update({
      broadcaster_disconnect_check_at: null,
      broadcaster_disconnect_reason: null,
    })
    .eq("id", sessionId)
    .eq("room_id", roomId)
}

/** True when a LiveKit webhook event predates the active broadcast session. */
export function isStaleLiveKitBroadcastWebhookEvent(
  eventCreatedAt: number | bigint | undefined,
  sessionStartedAtIso: string
): boolean {
  if (eventCreatedAt == null) return false
  const raw = Number(eventCreatedAt)
  const eventMs = raw > 1e12 ? raw / 1_000_000 : raw * 1000
  const startedMs = new Date(sessionStartedAtIso).getTime()
  return eventMs < startedMs - 2_000
}
