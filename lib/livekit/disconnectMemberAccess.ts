import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  canModerateRoomMemberTarget,
  canModerateTradeRoom,
  memberHasModeratorTag,
} from "@/lib/tradeRoomModerationPermission.ts"
import { canManageTradeRoom } from "@/lib/tradeRoomManagementPermission.ts"

export type DisconnectMemberAccess =
  | { ok: true; roomId: string; userId: string }
  | { ok: false; status: number; error: string }

/** Actor may disconnect self, or a moderator may disconnect a target member. */
export async function resolveDisconnectMemberAccess(
  admin: SupabaseClient<Database>,
  options: {
    actorUserId: string
    roomId: string
    targetUserId: string
  }
): Promise<DisconnectMemberAccess> {
  const { actorUserId, roomId, targetUserId } = options

  if (actorUserId === targetUserId) {
    return { ok: true, roomId, userId: targetUserId }
  }

  const { data: roomRow } = await admin
    .from("rooms")
    .select("owner_user_id, room_kind")
    .eq("id", roomId)
    .maybeSingle()

  if (!roomRow) {
    return { ok: false, status: 404, error: "Trade Room not found." }
  }

  const { data: adminRow } = await admin
    .from("admin_users")
    .select("user_id")
    .eq("user_id", actorUserId)
    .maybeSingle()

  const { data: tags } = await admin
    .from("room_member_tags")
    .select("id, name")
    .eq("room_id", roomId)

  const tagList = tags ?? []

  const { data: actorAssignments } = await admin
    .from("room_member_tag_assignments")
    .select("tag_id")
    .eq("room_id", roomId)
    .eq("user_id", actorUserId)

  const actorTagIds = (actorAssignments ?? []).map((r) => r.tag_id)
  const hasModeratorTag = memberHasModeratorTag({
    tagIds: actorTagIds,
    tags: tagList,
  })

  const canManage = canManageTradeRoom({
    viewerId: actorUserId,
    ownerUserId: roomRow.owner_user_id,
    roomKind: roomRow.room_kind,
    isPlatformAdmin: Boolean(adminRow),
  })

  const canModerate = canModerateTradeRoom({
    viewerId: actorUserId,
    ownerUserId: roomRow.owner_user_id,
    hasModeratorTag,
    roomKind: roomRow.room_kind,
    isPlatformAdmin: Boolean(adminRow),
  })

  const { data: targetAssignments } = await admin
    .from("room_member_tag_assignments")
    .select("tag_id")
    .eq("room_id", roomId)
    .eq("user_id", targetUserId)

  const targetTagIds = (targetAssignments ?? []).map((r) => r.tag_id)

  if (
    !canModerateRoomMemberTarget({
      viewerId: actorUserId,
      ownerUserId: roomRow.owner_user_id,
      targetUserId,
      targetTagIds,
      tags: tagList,
      canManageRoom: canManage,
      canModerateRoom: canModerate,
    })
  ) {
    return { ok: false, status: 403, error: "Permission denied." }
  }

  return { ok: true, roomId, userId: targetUserId }
}
