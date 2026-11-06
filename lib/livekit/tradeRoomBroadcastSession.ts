import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  normalizeTradeRoomBroadcastVideoSource,
  normalizeTradeRoomBroadcastVoiceMode,
  type TradeRoomBroadcastVideoSource,
  type TradeRoomBroadcastVoiceMode,
} from "./tradeRoomBroadcastVoiceMode.ts"
import { isBroadcasterConnectedInBroadcastRoom } from "./liveKitRoomService.ts"

export type ActiveTradeRoomBroadcast = {
  id: string
  roomId: string
  broadcasterUserId: string
  startedAt: string
  broadcasterDisplayName: string | null
  voiceMode: TradeRoomBroadcastVoiceMode
  videoSource: TradeRoomBroadcastVideoSource
}

const STALE_BROADCAST_MS = 6 * 60 * 60 * 1000

function broadcastsTable(admin: SupabaseClient<Database>) {
  return admin.from("room_live_broadcasts")
}

export async function recoverStaleTradeRoomBroadcast(
  admin: SupabaseClient<Database>,
  roomId: string
): Promise<void> {
  const cutoff = new Date(Date.now() - STALE_BROADCAST_MS).toISOString()
  await broadcastsTable(admin)
    .update({
      ended_at: new Date().toISOString(),
      ended_reason: "stale_timeout",
    })
    .eq("room_id", roomId)
    .is("ended_at", null)
    .lt("started_at", cutoff)
}

export async function getActiveTradeRoomBroadcast(
  admin: SupabaseClient<Database>,
  roomId: string
): Promise<ActiveTradeRoomBroadcast | null> {
  await recoverStaleTradeRoomBroadcast(admin, roomId)

  const { data, error } = await broadcastsTable(admin)
    .select("id, room_id, broadcaster_user_id, started_at, voice_mode, video_source")
    .eq("room_id", roomId)
    .is("ended_at", null)
    .maybeSingle()

  if (error) {
    console.error("[livekit/broadcast] active lookup failed", error.message)
    return null
  }

  const row = data
  if (!row) return null

  const { data: profileRow } = await admin
    .from("profiles")
    .select("username, name")
    .eq("id", row.broadcaster_user_id)
    .maybeSingle()

  const broadcasterDisplayName =
    profileRow?.name?.trim() ||
    profileRow?.username?.trim() ||
    null

  return {
    id: row.id,
    roomId: row.room_id,
    broadcasterUserId: row.broadcaster_user_id,
    startedAt: row.started_at,
    broadcasterDisplayName,
    voiceMode: normalizeTradeRoomBroadcastVoiceMode(row.voice_mode),
    videoSource: normalizeTradeRoomBroadcastVideoSource(row.video_source),
  }
}

export async function claimTradeRoomBroadcastSession(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    broadcasterUserId: string
    voiceMode: TradeRoomBroadcastVoiceMode
    videoSource: TradeRoomBroadcastVideoSource
  }
): Promise<
  | { ok: true; session: ActiveTradeRoomBroadcast }
  | { ok: false; status: number; error: string }
> {
  const { roomId, broadcasterUserId } = options
  await recoverStaleTradeRoomBroadcast(admin, roomId)

  const existing = await getActiveTradeRoomBroadcast(admin, roomId)
  if (existing) {
    if (existing.broadcasterUserId !== broadcasterUserId) {
      return {
        ok: false,
        status: 409,
        error: "Someone is already live in this Trade Room.",
      }
    }

    const stillConnected = await isBroadcasterConnectedInBroadcastRoom(
      roomId,
      broadcasterUserId
    )
    if (stillConnected) {
      return {
        ok: false,
        status: 409,
        error:
          "You are already live in another tab or device. End that stream before starting again.",
      }
    }

    const ended = await endTradeRoomBroadcastSession(admin, {
      roomId,
      sessionId: existing.id,
      actorUserId: broadcasterUserId,
      reason: "superseded_start",
    })
    if (!ended.ok) {
      return {
        ok: false,
        status: 409,
        error:
          "A previous stream is still winding down. Wait a moment and try again.",
      }
    }
    const { evictBroadcastRoomParticipants, deleteLiveKitBroadcastRoomIfEmpty } =
      await import("./tradeRoomBroadcastReconcile.ts")
    await evictBroadcastRoomParticipants(roomId)
    await deleteLiveKitBroadcastRoomIfEmpty(roomId)
  }

  const { data, error } = await broadcastsTable(admin)
    .insert({
      room_id: roomId,
      broadcaster_user_id: broadcasterUserId,
      voice_mode: options.voiceMode,
      video_source: options.videoSource,
    })
    .select("id, room_id, broadcaster_user_id, started_at, voice_mode, video_source")
    .single()

  if (error) {
    if (error.code === "23505") {
      return {
        ok: false,
        status: 409,
        error: "Someone is already live in this Trade Room.",
      }
    }
    console.error("[livekit/broadcast] claim failed", error.message)
    return { ok: false, status: 500, error: "Could not start broadcast session." }
  }

  const row = data
  const { data: profileRow } = await admin
    .from("profiles")
    .select("username, name")
    .eq("id", broadcasterUserId)
    .maybeSingle()

  const broadcasterDisplayName =
    profileRow?.name?.trim() ||
    profileRow?.username?.trim() ||
    null

  return {
    ok: true,
    session: {
      id: row.id,
      roomId: row.room_id,
      broadcasterUserId: row.broadcaster_user_id,
      startedAt: row.started_at,
      broadcasterDisplayName,
      voiceMode: normalizeTradeRoomBroadcastVoiceMode(row.voice_mode),
      videoSource: normalizeTradeRoomBroadcastVideoSource(row.video_source),
    },
  }
}

export async function endTradeRoomBroadcastSession(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
    actorUserId: string
    reason: string
    allowModeratorForce?: boolean
    moderatorUserIds?: string[]
  }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { data: active, error: loadErr } = await broadcastsTable(admin)
    .select("id, room_id, broadcaster_user_id, ended_at")
    .eq("id", options.sessionId)
    .eq("room_id", options.roomId)
    .maybeSingle()

  if (loadErr) {
    return { ok: false, status: 500, error: "Could not load broadcast session." }
  }

  const row = active
  if (!row || row.ended_at != null) {
    return { ok: true }
  }

  const isBroadcaster = row.broadcaster_user_id === options.actorUserId
  const isModeratorForce =
    options.allowModeratorForce &&
    (options.moderatorUserIds?.includes(options.actorUserId) ?? false)

  if (!isBroadcaster && !isModeratorForce) {
    return {
      ok: false,
      status: 403,
      error: "Only the broadcaster or a moderator can stop this stream.",
    }
  }

  const { error: updateErr } = await broadcastsTable(admin)
    .update({
      ended_at: new Date().toISOString(),
      ended_reason: options.reason.slice(0, 120),
    })
    .eq("id", options.sessionId)
    .eq("room_id", options.roomId)
    .is("ended_at", null)

  if (updateErr) {
    return { ok: false, status: 500, error: "Could not end broadcast session." }
  }

  const { clearBroadcastInteractiveStateForSession } = await import(
    "./tradeRoomBroadcastInteractiveState.ts"
  )
  await clearBroadcastInteractiveStateForSession(admin, options.sessionId)

  return { ok: true }
}

/** Webhook / server cleanup — ends only if session id still matches active row. */
export async function endTradeRoomBroadcastIfActive(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
    broadcasterUserId: string
    reason: string
  }
): Promise<boolean> {
  const { data, error } = await broadcastsTable(admin)
    .update({
      ended_at: new Date().toISOString(),
      ended_reason: options.reason.slice(0, 120),
      last_livekit_signal_at: new Date().toISOString(),
    })
    .eq("id", options.sessionId)
    .eq("room_id", options.roomId)
    .eq("broadcaster_user_id", options.broadcasterUserId)
    .is("ended_at", null)
    .select("id")

  if (error) {
    console.error("[livekit/broadcast] webhook end failed", error.message)
    return false
  }

  if (!data?.length) {
    return false
  }

  const { clearBroadcastInteractiveStateForSession } = await import(
    "./tradeRoomBroadcastInteractiveState.ts"
  )
  await clearBroadcastInteractiveStateForSession(admin, options.sessionId)

  return true
}
