import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  normalizeTradeRoomBroadcastVideoSource,
  normalizeTradeRoomBroadcastVoiceMode,
  type TradeRoomBroadcastVideoSource,
  type TradeRoomBroadcastVoiceMode,
} from "./tradeRoomBroadcastVoiceMode.ts"
import { isBroadcasterConnectedInBroadcastRoom } from "./liveKitRoomService.ts"
import { deleteLiveKitIngress } from "./liveKitIngressService.ts"

export type TradeRoomBroadcastSource = "browser" | "obs"

/** `preparing` = host-only OBS setup; not discoverable as live. */
export type TradeRoomBroadcastVisibility = "public" | "preparing"

export type ActiveTradeRoomBroadcast = {
  id: string
  roomId: string
  broadcasterUserId: string
  startedAt: string
  broadcasterDisplayName: string | null
  voiceMode: TradeRoomBroadcastVoiceMode
  videoSource: TradeRoomBroadcastVideoSource
  broadcastSource: TradeRoomBroadcastSource
  /** LiveKit identity for OBS/Ingress program feed; null for browser-only. */
  primaryMediaPublisherIdentity: string | null
  livekitIngressId: string | null
  ingressStatusSnapshot: string | null
  visibility: TradeRoomBroadcastVisibility
  /** When push fan-out for go-live ran (at most once per session). */
  goLiveNotifiedAt: string | null
}

function normalizeBroadcastSource(
  raw: string | null | undefined
): TradeRoomBroadcastSource {
  const v = (raw ?? "browser").trim().toLowerCase()
  return v === "obs" ? "obs" : "browser"
}

/**
 * DB visibility: `preparing` / `public`. Missing/null must NOT default to public for OBS rows
 * (would leak "public" status and open viewer token paths incorrectly).
 * Legacy browser rows without `visibility` remain public.
 */
export function normalizeVisibilityFromRow(
  row: Record<string, unknown>
): TradeRoomBroadcastVisibility {
  const raw = row.visibility as string | null | undefined
  if (raw != null && String(raw).trim() !== "") {
    const v = String(raw).trim().toLowerCase()
    return v === "preparing" ? "preparing" : "public"
  }
  const videoSource = normalizeTradeRoomBroadcastVideoSource(row.video_source as string)
  const broadcastSource = normalizeBroadcastSource(row.broadcast_source as string | undefined)
  if (videoSource === "obs" || broadcastSource === "obs") {
    return "preparing"
  }
  return "public"
}

function rowToActive(
  row: Record<string, unknown>,
  broadcasterDisplayName: string | null
): ActiveTradeRoomBroadcast {
  return {
    id: row.id as string,
    roomId: row.room_id as string,
    broadcasterUserId: row.broadcaster_user_id as string,
    startedAt: row.started_at as string,
    broadcasterDisplayName,
    voiceMode: normalizeTradeRoomBroadcastVoiceMode(row.voice_mode as string),
    videoSource: normalizeTradeRoomBroadcastVideoSource(row.video_source as string),
    broadcastSource: normalizeBroadcastSource(row.broadcast_source as string | undefined),
    primaryMediaPublisherIdentity:
      (row.primary_media_publisher_identity as string | null)?.trim() || null,
    livekitIngressId: (row.livekit_ingress_id as string | null)?.trim() || null,
    ingressStatusSnapshot:
      (row.ingress_status_snapshot as string | null)?.trim() || null,
    visibility: normalizeVisibilityFromRow(row),
    goLiveNotifiedAt:
      (row.go_live_notified_at as string | null)?.trim() || null,
  }
}

const STALE_BROADCAST_MS = 6 * 60 * 60 * 1000
/** Abandoned OBS preparation (credentials created but never published). */
const STALE_OBS_PREPARING_MS = 2 * 60 * 60 * 1000

function broadcastsTable(admin: SupabaseClient<Database>) {
  return admin.from("room_live_broadcasts")
}

export async function recoverStaleTradeRoomBroadcast(
  admin: SupabaseClient<Database>,
  roomId: string
): Promise<void> {
  const now = Date.now()
  const cutoff = new Date(now - STALE_BROADCAST_MS).toISOString()
  const prepCutoff = new Date(now - STALE_OBS_PREPARING_MS).toISOString()
  await broadcastsTable(admin)
    .update({
      ended_at: new Date().toISOString(),
      ended_reason: "stale_timeout",
    })
    .eq("room_id", roomId)
    .is("ended_at", null)
    .lt("started_at", cutoff)

  const { data: stalePrepRows } = await broadcastsTable(admin)
    .select("id, room_id, broadcaster_user_id")
    .eq("room_id", roomId)
    .eq("visibility", "preparing")
    .is("ended_at", null)
    .lt("started_at", prepCutoff)

  for (const row of stalePrepRows ?? []) {
    const sid = row.id as string
    const rrid = row.room_id as string
    const uid = row.broadcaster_user_id as string
    const ended = await endTradeRoomBroadcastSession(admin, {
      roomId: rrid,
      sessionId: sid,
      actorUserId: uid,
      reason: "obs_preparing_timeout",
    })
    if (ended.ok) {
      const { evictBroadcastRoomParticipants, deleteLiveKitBroadcastRoomIfEmpty } =
        await import("./tradeRoomBroadcastReconcile.ts")
      await evictBroadcastRoomParticipants(rrid)
      await deleteLiveKitBroadcastRoomIfEmpty(rrid)
    }
  }
}

export type GetActiveTradeRoomBroadcastOptions = {
  /** Skip profile lookup (saves a Supabase round-trip for frequent polling). */
  lite?: boolean
  /** Skip stale-session cleanup (frequent polling should not run UPDATE every time). */
  skipRecoverStale?: boolean
  /**
   * - `any`: row with ended_at null (webhooks, ingress, supersede checks).
   * - `public_or_viewer` (default): public rows only when viewerUserId omitted; with viewerUserId,
   *   also returns preparing rows when that user is the broadcaster (host setup).
   */
  activeScope?: "any" | "public_or_viewer"
  viewerUserId?: string | null
}

export async function getActiveTradeRoomBroadcast(
  admin: SupabaseClient<Database>,
  roomId: string,
  options?: GetActiveTradeRoomBroadcastOptions
): Promise<ActiveTradeRoomBroadcast | null> {
  const lite = options?.lite === true
  const skipRecoverStale = options?.skipRecoverStale === true
  const activeScope = options?.activeScope ?? "public_or_viewer"
  const viewerUserId = options?.viewerUserId?.trim() || null

  if (!skipRecoverStale) {
    await recoverStaleTradeRoomBroadcast(admin, roomId)
  }

  const { data, error } = await broadcastsTable(admin)
    .select(
      "id, room_id, broadcaster_user_id, started_at, voice_mode, video_source, broadcast_source, primary_media_publisher_identity, livekit_ingress_id, ingress_status_snapshot, visibility, go_live_notified_at"
    )
    .eq("room_id", roomId)
    .is("ended_at", null)
    .maybeSingle()

  if (error) {
    console.error("[livekit/broadcast] active lookup failed", error.message)
    return null
  }

  const row = data
  if (!row) return null

  if (activeScope === "public_or_viewer") {
    const vis = normalizeVisibilityFromRow(row as Record<string, unknown>)
    if (vis === "preparing") {
      if (!viewerUserId || row.broadcaster_user_id !== viewerUserId) {
        return null
      }
    }
  }

  let broadcasterDisplayName: string | null = null
  if (!lite) {
    const { data: profileRow } = await admin
      .from("profiles")
      .select("username, name")
      .eq("id", row.broadcaster_user_id)
      .maybeSingle()

    broadcasterDisplayName =
      profileRow?.name?.trim() ||
      profileRow?.username?.trim() ||
      null
  }

  return rowToActive(row as Record<string, unknown>, broadcasterDisplayName)
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

  const existing = await getActiveTradeRoomBroadcast(admin, roomId, {
    activeScope: "any",
  })
  if (existing) {
    if (existing.broadcasterUserId !== broadcasterUserId) {
      return {
        ok: false,
        status: 409,
        error: "Someone is already live in this Trade Room.",
      }
    }

    /** Same host refreshing Stage 1 — reuse row (no duplicate session / notification). */
    if (
      options.videoSource === "obs" &&
      existing.videoSource === "obs" &&
      existing.visibility === "preparing"
    ) {
      if (existing.voiceMode !== options.voiceMode) {
        const { error: vmErr } = await broadcastsTable(admin)
          .update({ voice_mode: options.voiceMode })
          .eq("id", existing.id)
          .eq("room_id", roomId)
          .is("ended_at", null)
        if (vmErr) {
          console.error("[livekit/broadcast] voice_mode update failed", vmErr.message)
        }
      }
      const refreshed = await getActiveTradeRoomBroadcast(admin, roomId, {
        activeScope: "any",
        skipRecoverStale: true,
      })
      if (refreshed?.id === existing.id) {
        return { ok: true, session: refreshed }
      }
    }

    const stillConnected = await isBroadcasterConnectedInBroadcastRoom(
      roomId,
      broadcasterUserId,
      existing.primaryMediaPublisherIdentity
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

  const isObsSession = options.videoSource === "obs"

  const { data, error } = await broadcastsTable(admin)
    .insert({
      room_id: roomId,
      broadcaster_user_id: broadcasterUserId,
      voice_mode: options.voiceMode,
      video_source: options.videoSource,
      /** OBS encoder sessions use ingress; keep in sync with UI and status API from row one. */
      broadcast_source: isObsSession ? "obs" : "browser",
      visibility: isObsSession ? "preparing" : "public",
    })
    .select(
      "id, room_id, broadcaster_user_id, started_at, voice_mode, video_source, broadcast_source, primary_media_publisher_identity, livekit_ingress_id, ingress_status_snapshot, visibility, go_live_notified_at"
    )
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
    session: rowToActive(row as Record<string, unknown>, broadcasterDisplayName),
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
    .select("id, room_id, broadcaster_user_id, ended_at, livekit_ingress_id")
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

  const ingressId =
    (active as { livekit_ingress_id?: string | null }).livekit_ingress_id?.trim() ??
    ""
  if (ingressId) {
    await deleteLiveKitIngress(ingressId)
  }

  const { clearBroadcastInteractiveStateForSession } = await import(
    "./tradeRoomBroadcastInteractiveState.ts"
  )
  await clearBroadcastInteractiveStateForSession(admin, options.sessionId)

  return { ok: true }
}

export async function updateBroadcastIngressSnapshot(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
    ingressStatusLabel: string | null
  }
): Promise<void> {
  const label = options.ingressStatusLabel?.trim() || null
  const { error } = await broadcastsTable(admin)
    .update({
      ingress_status_snapshot: label,
      last_livekit_signal_at: new Date().toISOString(),
    })
    .eq("id", options.sessionId)
    .eq("room_id", options.roomId)
    .is("ended_at", null)

  if (error) {
    console.error("[livekit/broadcast] ingress snapshot update failed", error.message)
  }
}

/**
 * Attach OBS RTMP ingress to an active session (server-only). Does not persist stream keys.
 */
export async function attachObsRtmpIngressToActiveSession(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    broadcasterUserId: string
    sessionId: string
    livekitIngressId: string
    primaryMediaPublisherIdentity: string
    ingressStatusLabel: string | null
  }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const label = options.ingressStatusLabel?.trim() || null
  const { data, error } = await broadcastsTable(admin)
    .update({
      broadcast_source: "obs",
      primary_media_publisher_identity: options.primaryMediaPublisherIdentity,
      livekit_ingress_id: options.livekitIngressId.trim(),
      ingress_status_snapshot: label,
      last_livekit_signal_at: new Date().toISOString(),
    })
    .eq("id", options.sessionId)
    .eq("room_id", options.roomId)
    .eq("broadcaster_user_id", options.broadcasterUserId)
    .is("ended_at", null)
    .select("id")

  if (error) {
    console.error("[livekit/broadcast] attach OBS ingress failed", error.message)
    return { ok: false, status: 500, error: "Could not attach OBS ingress to session." }
  }
  if (!data?.length) {
    return {
      ok: false,
      status: 409,
      error: "No active broadcast session found for this room.",
    }
  }
  return { ok: true }
}

/**
 * Clear OBS ingress metadata (revoke). Idempotent; ignores missing rows.
 */
export async function clearObsIngressMetadata(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
    broadcasterUserId: string
  }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { data, error } = await broadcastsTable(admin)
    .update({
      broadcast_source: "browser",
      primary_media_publisher_identity: null,
      livekit_ingress_id: null,
      ingress_status_snapshot: null,
      last_livekit_signal_at: new Date().toISOString(),
    })
    .eq("id", options.sessionId)
    .eq("room_id", options.roomId)
    .eq("broadcaster_user_id", options.broadcasterUserId)
    .is("ended_at", null)
    .select("id")

  if (error) {
    console.error("[livekit/broadcast] clear OBS metadata failed", error.message)
    return { ok: false, status: 500, error: "Could not clear OBS ingress metadata." }
  }
  if (!data?.length) {
    return { ok: true }
  }
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
  const { data: row, error: loadErr } = await broadcastsTable(admin)
    .select("id, livekit_ingress_id")
    .eq("id", options.sessionId)
    .eq("room_id", options.roomId)
    .eq("broadcaster_user_id", options.broadcasterUserId)
    .is("ended_at", null)
    .maybeSingle()

  if (loadErr || !row) {
    if (loadErr) {
      console.error("[livekit/broadcast] webhook end load failed", loadErr.message)
    }
    return false
  }

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

  const ingressId =
    (row as { livekit_ingress_id?: string | null }).livekit_ingress_id?.trim() ?? ""
  if (ingressId) {
    await deleteLiveKitIngress(ingressId)
  }

  const { clearBroadcastInteractiveStateForSession } = await import(
    "./tradeRoomBroadcastInteractiveState.ts"
  )
  await clearBroadcastInteractiveStateForSession(admin, options.sessionId)

  return true
}
