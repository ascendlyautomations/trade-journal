import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { getActiveTradeRoomBroadcast } from "./tradeRoomBroadcastSession.ts"
import { listLiveKitBroadcastParticipantIdentities } from "./liveKitRoomService.ts"
import { normalizeTradeRoomBroadcastVideoSource } from "./tradeRoomBroadcastVoiceMode.ts"

export type BroadcastInteractiveProfile = {
  userId: string
  username: string | null
  displayName: string | null
  avatarUrl: string | null
}

export type BroadcastInteractiveSnapshot = {
  sessionId: string
  roomId: string
  broadcasterUserId: string
  /** browser vs obs — Phase 2 playback uses primaryMediaPublisherIdentity when obs. */
  broadcastSource: "browser" | "obs"
  primaryMediaPublisherIdentity: string | null
  livekitIngressId: string | null
  ingressStatusSnapshot: string | null
  voiceMode: "broadcast_only" | "open_voice"
  raisedHands: Array<{ userId: string; raisedAt: string }>
  speakerGrants: string[]
  sessionBlocks: string[]
  pendingInvitations: Array<{ userId: string; invitationId: string }>
  pendingInvitationForViewer: { invitationId: string } | null
  /** True when the viewer is blocked from rejoining this broadcast session. */
  blockedFromBroadcastRejoin: boolean
  /** True when this user currently appears as a LiveKit participant in the broadcast room. */
  presentInLiveKitBroadcastRoom: boolean
  /**
   * @deprecated Same as `blockedFromBroadcastRejoin` (historic name). Prefer `blockedFromBroadcastRejoin`
   * or `presentInLiveKitBroadcastRoom` for removal vs block.
   */
  removedFromStream: boolean
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export async function loadBroadcastInteractiveProfiles(
  admin: SupabaseClient<Database>,
  userIds: string[]
): Promise<Map<string, BroadcastInteractiveProfile>> {
  const unique = [
    ...new Set(
      userIds.filter((id) => {
        const t = id?.trim()
        return Boolean(t && UUID_RE.test(t))
      })
    ),
  ]
  const map = new Map<string, BroadcastInteractiveProfile>()
  if (unique.length === 0) return map

  const { data } = await admin
    .from("profiles")
    .select("id, username, name, avatar_url")
    .in("id", unique)

  for (const row of data ?? []) {
    map.set(row.id, {
      userId: row.id,
      username: row.username?.trim() || null,
      displayName: row.name?.trim() || row.username?.trim() || null,
      avatarUrl: row.avatar_url ?? null,
    })
  }
  return map
}

export async function assertActiveBroadcastSession(
  admin: SupabaseClient<Database>,
  roomId: string,
  sessionId: string
): Promise<
  | { ok: true; broadcasterUserId: string; voiceMode: "broadcast_only" | "open_voice" }
  | { ok: false; status: number; error: string }
> {
  const active = await getActiveTradeRoomBroadcast(admin, roomId, {
    activeScope: "any",
  })
  if (!active || active.id !== sessionId) {
    return { ok: false, status: 404, error: "Broadcast session is not active." }
  }
  if (active.visibility === "preparing") {
    return {
      ok: false,
      status: 404,
      error: "This stream is not live yet.",
    }
  }
  return {
    ok: true,
    broadcasterUserId: active.broadcasterUserId,
    voiceMode: active.voiceMode,
  }
}

export async function hasActiveBroadcastSpeakerGrant(
  admin: SupabaseClient<Database>,
  sessionId: string,
  userId: string
): Promise<boolean> {
  const { data } = await admin
    .from("room_live_broadcast_speaker_grants")
    .select("user_id")
    .eq("broadcast_session_id", sessionId)
    .eq("user_id", userId)
    .is("revoked_at", null)
    .maybeSingle()
  return Boolean(data)
}

export async function isUserBlockedFromBroadcastSession(
  admin: SupabaseClient<Database>,
  sessionId: string,
  userId: string
): Promise<boolean> {
  const { data } = await admin
    .from("room_live_broadcast_session_blocks")
    .select("user_id")
    .eq("broadcast_session_id", sessionId)
    .eq("user_id", userId)
    .maybeSingle()
  return Boolean(data)
}

export async function setBroadcastHandRaised(
  admin: SupabaseClient<Database>,
  options: { sessionId: string; userId: string; raised: boolean }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  if (options.raised) {
    const { error } = await admin.from("room_live_broadcast_hands").upsert(
      {
        broadcast_session_id: options.sessionId,
        user_id: options.userId,
        raised_at: new Date().toISOString(),
      },
      { onConflict: "broadcast_session_id,user_id" }
    )
    if (error) {
      return { ok: false, status: 500, error: "Could not save raised hand." }
    }
    return { ok: true }
  }

  const { error } = await admin
    .from("room_live_broadcast_hands")
    .delete()
    .eq("broadcast_session_id", options.sessionId)
    .eq("user_id", options.userId)

  if (error) {
    return { ok: false, status: 500, error: "Could not lower hand." }
  }
  return { ok: true }
}

export async function dismissBroadcastHand(
  admin: SupabaseClient<Database>,
  options: { sessionId: string; targetUserId: string }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  return setBroadcastHandRaised(admin, {
    sessionId: options.sessionId,
    userId: options.targetUserId,
    raised: false,
  })
}

export async function loadBroadcastInteractiveSnapshot(
  admin: SupabaseClient<Database>,
  options: { roomId: string; viewerUserId: string }
): Promise<
  | {
      ok: true
      snapshot: BroadcastInteractiveSnapshot | null
      profiles: BroadcastInteractiveProfile[]
    }
  | { ok: false; status: number; error: string }
> {
  const active = await getActiveTradeRoomBroadcast(admin, options.roomId, {
    viewerUserId: options.viewerUserId,
  })
  if (!active) {
    return { ok: true, snapshot: null, profiles: [] }
  }

  if (
    active.visibility === "preparing" &&
    active.broadcasterUserId !== options.viewerUserId
  ) {
    return { ok: true, snapshot: null, profiles: [] }
  }

  const blocked = await isUserBlockedFromBroadcastSession(
    admin,
    active.id,
    options.viewerUserId
  )

  const liveKitIdentities = await listLiveKitBroadcastParticipantIdentities(active.roomId)
  const presentInLiveKitBroadcastRoom = liveKitIdentities.includes(options.viewerUserId)

  const [{ data: hands }, { data: grants }, { data: blocks }, { data: invites }] =
    await Promise.all([
      admin
        .from("room_live_broadcast_hands")
        .select("user_id, raised_at")
        .eq("broadcast_session_id", active.id)
        .order("raised_at", { ascending: false }),
      admin
        .from("room_live_broadcast_speaker_grants")
        .select("user_id")
        .eq("broadcast_session_id", active.id)
        .is("revoked_at", null),
      admin
        .from("room_live_broadcast_session_blocks")
        .select("user_id")
        .eq("broadcast_session_id", active.id),
      admin
        .from("room_live_broadcast_invitations")
        .select("id, user_id, status")
        .eq("broadcast_session_id", active.id)
        .in("status", ["pending", "accepted"]),
    ])

  const pendingForViewer =
    (invites ?? []).find(
      (row) => row.user_id === options.viewerUserId && row.status === "pending"
    ) ?? null

  const profileIds = new Set<string>([active.broadcasterUserId])
  for (const identity of liveKitIdentities) {
    profileIds.add(identity)
  }
  for (const h of hands ?? []) profileIds.add(h.user_id)
  for (const g of grants ?? []) profileIds.add(g.user_id)
  for (const b of blocks ?? []) profileIds.add(b.user_id)
  for (const i of invites ?? []) profileIds.add(i.user_id)

  const profileMap = await loadBroadcastInteractiveProfiles(admin, [...profileIds])

  return {
    ok: true,
    snapshot: {
      sessionId: active.id,
      roomId: active.roomId,
      broadcasterUserId: active.broadcasterUserId,
      broadcastSource: active.broadcastSource,
      primaryMediaPublisherIdentity: active.primaryMediaPublisherIdentity,
      livekitIngressId: active.livekitIngressId,
      ingressStatusSnapshot: active.ingressStatusSnapshot,
      voiceMode: active.voiceMode,
      raisedHands: (hands ?? []).map((h) => ({
        userId: h.user_id,
        raisedAt: h.raised_at,
      })),
      speakerGrants: (grants ?? []).map((g) => g.user_id),
      sessionBlocks: (blocks ?? []).map((b) => b.user_id),
      pendingInvitations: (invites ?? [])
        .filter((i) => i.status === "pending")
        .map((i) => ({ userId: i.user_id, invitationId: i.id })),
      pendingInvitationForViewer: pendingForViewer
        ? { invitationId: pendingForViewer.id }
        : null,
      blockedFromBroadcastRejoin: blocked,
      presentInLiveKitBroadcastRoom,
      removedFromStream: blocked,
    },
    profiles: [...profileMap.values()],
  }
}

export async function grantBroadcastSpeaker(
  admin: SupabaseClient<Database>,
  options: {
    sessionId: string
    targetUserId: string
    grantedBy: string
  }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { error } = await admin.from("room_live_broadcast_speaker_grants").upsert(
    {
      broadcast_session_id: options.sessionId,
      user_id: options.targetUserId,
      granted_by: options.grantedBy,
      granted_at: new Date().toISOString(),
      revoked_at: null,
    },
    { onConflict: "broadcast_session_id,user_id" }
  )
  if (error) {
    return { ok: false, status: 500, error: "Could not grant speaker permission." }
  }
  return { ok: true }
}

export async function revokeBroadcastSpeaker(
  admin: SupabaseClient<Database>,
  options: { sessionId: string; targetUserId: string }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { error } = await admin
    .from("room_live_broadcast_speaker_grants")
    .update({ revoked_at: new Date().toISOString() })
    .eq("broadcast_session_id", options.sessionId)
    .eq("user_id", options.targetUserId)
    .is("revoked_at", null)

  if (error) {
    return { ok: false, status: 500, error: "Could not revoke speaker permission." }
  }
  return { ok: true }
}

export async function blockBroadcastSessionParticipant(
  admin: SupabaseClient<Database>,
  options: {
    sessionId: string
    targetUserId: string
    blockedBy: string
  }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { error } = await admin.from("room_live_broadcast_session_blocks").upsert(
    {
      broadcast_session_id: options.sessionId,
      user_id: options.targetUserId,
      blocked_by: options.blockedBy,
      blocked_at: new Date().toISOString(),
    },
    { onConflict: "broadcast_session_id,user_id" }
  )
  if (error) {
    return { ok: false, status: 500, error: "Could not block participant." }
  }
  return { ok: true }
}

export async function createBroadcastSpeakInvitation(
  admin: SupabaseClient<Database>,
  options: {
    sessionId: string
    targetUserId: string
    invitedBy: string
  }
): Promise<
  | { ok: true; invitationId: string }
  | { ok: false; status: number; error: string }
> {
  await admin
    .from("room_live_broadcast_invitations")
    .update({ status: "revoked", responded_at: new Date().toISOString() })
    .eq("broadcast_session_id", options.sessionId)
    .eq("user_id", options.targetUserId)
    .eq("status", "pending")

  const { data, error } = await admin
    .from("room_live_broadcast_invitations")
    .insert({
      broadcast_session_id: options.sessionId,
      user_id: options.targetUserId,
      invited_by: options.invitedBy,
      status: "pending",
    })
    .select("id")
    .single()

  if (error || !data) {
    return { ok: false, status: 500, error: "Could not create invitation." }
  }
  return { ok: true, invitationId: data.id }
}

export async function respondBroadcastSpeakInvitation(
  admin: SupabaseClient<Database>,
  options: {
    invitationId: string
    userId: string
    accept: boolean
  }
): Promise<
    | {
      ok: true
      sessionId: string
      roomId: string
      broadcasterUserId: string
      startedAt: string
      voiceMode: "broadcast_only" | "open_voice"
      videoSource: "screen" | "camera" | "obs"
      broadcasterDisplayName: string | null
      broadcastSource: "browser" | "obs"
      primaryMediaPublisherIdentity: string | null
    }
  | { ok: false; status: number; error: string }
> {
  const { data: row, error: loadErr } = await admin
    .from("room_live_broadcast_invitations")
    .select("id, broadcast_session_id, user_id, status, invited_by")
    .eq("id", options.invitationId)
    .maybeSingle()

  if (loadErr || !row || row.user_id !== options.userId || row.status !== "pending") {
    return { ok: false, status: 404, error: "Invitation not found." }
  }

  const { data: sessionRow } = await admin
    .from("room_live_broadcasts")
    .select(
      "id, room_id, ended_at, broadcaster_user_id, started_at, voice_mode, video_source, broadcast_source, primary_media_publisher_identity"
    )
    .eq("id", row.broadcast_session_id)
    .maybeSingle()

  if (!sessionRow || sessionRow.ended_at != null) {
    return { ok: false, status: 404, error: "Broadcast session ended." }
  }

  const status = options.accept ? "accepted" : "declined"
  const { error: updateErr } = await admin
    .from("room_live_broadcast_invitations")
    .update({ status, responded_at: new Date().toISOString() })
    .eq("id", options.invitationId)

  if (updateErr) {
    return { ok: false, status: 500, error: "Could not respond to invitation." }
  }

  const { data: profileRow } = await admin
    .from("profiles")
    .select("username, name")
    .eq("id", sessionRow.broadcaster_user_id)
    .maybeSingle()

  const broadcasterDisplayName =
    profileRow?.name?.trim() || profileRow?.username?.trim() || null

  const broadcastSource =
    (sessionRow.broadcast_source as string | undefined)?.trim().toLowerCase() ===
    "obs"
      ? ("obs" as const)
      : ("browser" as const)

  return {
    ok: true,
    sessionId: sessionRow.id,
    roomId: sessionRow.room_id,
    broadcasterUserId: sessionRow.broadcaster_user_id,
    startedAt: sessionRow.started_at,
    voiceMode:
      sessionRow.voice_mode === "open_voice" ? "open_voice" : "broadcast_only",
    videoSource: normalizeTradeRoomBroadcastVideoSource(
      sessionRow.video_source as string
    ),
    broadcasterDisplayName,
    broadcastSource,
    primaryMediaPublisherIdentity:
      (sessionRow.primary_media_publisher_identity as string | null)?.trim() ||
      null,
  }
}

export async function clearBroadcastInteractiveStateForSession(
  admin: SupabaseClient<Database>,
  sessionId: string
): Promise<void> {
  await Promise.all([
    admin.from("room_live_broadcast_hands").delete().eq("broadcast_session_id", sessionId),
    admin
      .from("room_live_broadcast_invitations")
      .update({ status: "revoked", responded_at: new Date().toISOString() })
      .eq("broadcast_session_id", sessionId)
      .eq("status", "pending"),
  ])
}
