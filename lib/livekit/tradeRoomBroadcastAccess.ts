import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  canModerateTradeRoom,
  memberHasModeratorTag,
} from "@/lib/tradeRoomModerationPermission.ts"
import { canManageTradeRoom } from "@/lib/tradeRoomManagementPermission.ts"

import { mayStartTradeRoomBroadcast } from "./tradeRoomSharedBroadcast.ts"

export type TradeRoomBroadcastViewerAccess =
  | {
      ok: true
      roomId: string
      displayName: string | null
      canSubscribe: true
    }
  | { ok: false; status: number; error: string }

export type TradeRoomBroadcastControlAccess =
  | {
      ok: true
      roomId: string
      displayName: string | null
      canBroadcast: true
      isOwner: boolean
      isModerator: boolean
    }
  | { ok: false; status: number; error: string }

async function loadMemberAndRoom(
  admin: SupabaseClient<Database>,
  userId: string,
  roomId: string
): Promise<
  | {
      ok: true
      room: {
        owner_user_id: string | null
        room_kind: string | null
      }
    }
  | { ok: false; status: number; error: string }
> {
  const { data: banRow } = await admin
    .from("room_bans")
    .select("user_id")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .maybeSingle()

  if (banRow) {
    return { ok: false, status: 403, error: "You are banned from this Trade Room." }
  }

  const { data: memberRow, error: memberErr } = await admin
    .from("room_members")
    .select("left_at")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .maybeSingle()

  if (memberErr) {
    console.error("[livekit/broadcast] member lookup failed", memberErr.message)
    return { ok: false, status: 500, error: "Could not verify room membership." }
  }

  if (!memberRow || memberRow.left_at != null) {
    return {
      ok: false,
      status: 403,
      error: "Active room membership is required to watch or broadcast.",
    }
  }

  const { data: roomRow, error: roomErr } = await admin
    .from("rooms")
    .select("owner_user_id, room_kind")
    .eq("id", roomId)
    .maybeSingle()

  if (roomErr || !roomRow) {
    return { ok: false, status: 404, error: "Trade Room not found." }
  }

  return { ok: true, room: roomRow }
}

async function profileDisplayName(
  admin: SupabaseClient<Database>,
  userId: string
): Promise<string | null> {
  const { data: profileRow } = await admin
    .from("profiles")
    .select("username, name")
    .eq("id", userId)
    .maybeSingle()

  return (
    profileRow?.name?.trim() ||
    profileRow?.username?.trim() ||
    null
  )
}

export async function resolveTradeRoomBroadcastViewerAccess(
  admin: SupabaseClient<Database>,
  options: { userId: string; roomId: string }
): Promise<TradeRoomBroadcastViewerAccess> {
  const base = await loadMemberAndRoom(admin, options.userId, options.roomId)
  if (!base.ok) return base

  const displayName = await profileDisplayName(admin, options.userId)

  return {
    ok: true,
    roomId: options.roomId,
    displayName,
    canSubscribe: true,
  }
}

/** Phase 1: room owner or moderator may start a broadcast. */
export async function resolveTradeRoomBroadcastControlAccess(
  admin: SupabaseClient<Database>,
  options: { userId: string; roomId: string }
): Promise<TradeRoomBroadcastControlAccess> {
  const base = await loadMemberAndRoom(admin, options.userId, options.roomId)
  if (!base.ok) return base

  const { userId, roomId } = options
  const roomRow = base.room

  const { data: adminRow } = await admin
    .from("admin_users")
    .select("user_id")
    .eq("user_id", userId)
    .maybeSingle()

  const { data: tagRows } = await admin
    .from("room_member_tags")
    .select("id, name")
    .eq("room_id", roomId)

  const { data: assignmentRows } = await admin
    .from("room_member_tag_assignments")
    .select("tag_id")
    .eq("room_id", roomId)
    .eq("user_id", userId)

  const tagIds = (assignmentRows ?? []).map((r) => r.tag_id)
  const hasModeratorTag = memberHasModeratorTag({ tagIds, tags: tagRows ?? [] })
  const isPlatformAdmin = Boolean(adminRow)
  const isOwner = roomRow.owner_user_id === userId
  const canManage = canManageTradeRoom({
    viewerId: userId,
    ownerUserId: roomRow.owner_user_id,
    roomKind: roomRow.room_kind,
    isPlatformAdmin,
  })
  const canModerate = canModerateTradeRoom({
    viewerId: userId,
    ownerUserId: roomRow.owner_user_id,
    hasModeratorTag,
    roomKind: roomRow.room_kind,
    isPlatformAdmin,
  })

  const canBroadcast = mayStartTradeRoomBroadcast({
    isOwner,
    canManage,
    canModerate,
  })

  if (!canBroadcast) {
    return {
      ok: false,
      status: 403,
      error: "Only the room owner or moderators can start a live stream.",
    }
  }

  const displayName = await profileDisplayName(admin, userId)

  return {
    ok: true,
    roomId,
    displayName,
    canBroadcast: true,
    isOwner,
    isModerator: hasModeratorTag || canModerate,
  }
}
