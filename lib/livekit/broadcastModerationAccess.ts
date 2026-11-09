import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  canModerateRoomMemberTarget,
  canModerateTradeRoom,
  memberHasModeratorTag,
} from "@/lib/tradeRoomModerationPermission.ts"
import { canManageTradeRoom } from "@/lib/tradeRoomManagementPermission.ts"
export type BroadcastModerationAction =
  | "invite_speak"
  | "request_unmute"
  | "mute_speaker"
  | "revoke_speaker"
  | "remove_viewer"
  | "dismiss_hand"

export type BroadcastModerationActorAccess =
  | {
      ok: true
      roomId: string
      sessionId: string
      broadcasterUserId: string
      isBroadcaster: boolean
      canManage: boolean
      canModerate: boolean
    }
  | { ok: false; status: number; error: string }

const MOD_DELEGATED_ACTIONS = new Set<BroadcastModerationAction>([
  "dismiss_hand",
  "mute_speaker",
  "revoke_speaker",
  "remove_viewer",
])

const BROADCASTER_ONLY_ACTIONS = new Set<BroadcastModerationAction>([
  "invite_speak",
  "request_unmute",
])

export function broadcastModerationActionAllowed(options: {
  action: BroadcastModerationAction
  isBroadcaster: boolean
  canModerate: boolean
  canManage: boolean
}): boolean {
  if (options.isBroadcaster || options.canManage) {
    return true
  }
  if (!options.canModerate) {
    return false
  }
  if (BROADCASTER_ONLY_ACTIONS.has(options.action)) {
    return false
  }
  return MOD_DELEGATED_ACTIONS.has(options.action)
}

export async function resolveBroadcastModerationActorAccess(
  admin: SupabaseClient<Database>,
  options: {
    actorUserId: string
    roomId: string
    sessionId: string
    broadcasterUserId: string
  }
): Promise<BroadcastModerationActorAccess> {
  const { data: roomRow } = await admin
    .from("rooms")
    .select("owner_user_id, room_kind")
    .eq("id", options.roomId)
    .maybeSingle()

  if (!roomRow) {
    return { ok: false, status: 404, error: "Trade Room not found." }
  }

  const { data: adminRow } = await admin
    .from("admin_users")
    .select("user_id")
    .eq("user_id", options.actorUserId)
    .maybeSingle()

  const { data: tags } = await admin
    .from("room_member_tags")
    .select("id, name")
    .eq("room_id", options.roomId)

  const tagList = tags ?? []

  const { data: actorAssignments } = await admin
    .from("room_member_tag_assignments")
    .select("tag_id")
    .eq("room_id", options.roomId)
    .eq("user_id", options.actorUserId)

  const actorTagIds = (actorAssignments ?? []).map((r) => r.tag_id)
  const hasModeratorTag = memberHasModeratorTag({
    tagIds: actorTagIds,
    tags: tagList,
  })

  const canManage = canManageTradeRoom({
    viewerId: options.actorUserId,
    ownerUserId: roomRow.owner_user_id,
    roomKind: roomRow.room_kind,
    isPlatformAdmin: Boolean(adminRow),
  })

  const canModerate = canModerateTradeRoom({
    viewerId: options.actorUserId,
    ownerUserId: roomRow.owner_user_id,
    hasModeratorTag,
    roomKind: roomRow.room_kind,
    isPlatformAdmin: Boolean(adminRow),
  })

  const isBroadcaster = options.actorUserId === options.broadcasterUserId

  if (!isBroadcaster && !canModerate && !canManage) {
    return { ok: false, status: 403, error: "Permission denied." }
  }

  return {
    ok: true,
    roomId: options.roomId,
    sessionId: options.sessionId,
    broadcasterUserId: options.broadcasterUserId,
    isBroadcaster,
    canManage,
    canModerate,
  }
}

export async function resolveBroadcastModerationTargetAccess(
  admin: SupabaseClient<Database>,
  options: {
    actorUserId: string
    roomId: string
    targetUserId: string
    broadcasterUserId: string
    canManage: boolean
    canModerate: boolean
  }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  if (options.targetUserId === options.actorUserId) {
    return { ok: false, status: 400, error: "You cannot moderate yourself." }
  }

  if (options.targetUserId === options.broadcasterUserId) {
    return { ok: false, status: 400, error: "Invalid target participant." }
  }

  const { data: roomRow } = await admin
    .from("rooms")
    .select("owner_user_id")
    .eq("id", options.roomId)
    .maybeSingle()

  if (!roomRow) {
    return { ok: false, status: 404, error: "Trade Room not found." }
  }

  const { data: tags } = await admin
    .from("room_member_tags")
    .select("id, name")
    .eq("room_id", options.roomId)

  const tagList = tags ?? []

  const { data: targetAssignments } = await admin
    .from("room_member_tag_assignments")
    .select("tag_id")
    .eq("room_id", options.roomId)
    .eq("user_id", options.targetUserId)

  const targetTagIds = (targetAssignments ?? []).map((r) => r.tag_id)

  if (
    !canModerateRoomMemberTarget({
      viewerId: options.actorUserId,
      ownerUserId: roomRow.owner_user_id,
      targetUserId: options.targetUserId,
      targetTagIds,
      tags: tagList,
      canManageRoom: options.canManage,
      canModerateRoom: options.canModerate,
    })
  ) {
    return { ok: false, status: 403, error: "Permission denied." }
  }

  return { ok: true }
}
