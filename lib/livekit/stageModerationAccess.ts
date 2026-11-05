import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  canModerateRoomMemberTarget,
  canModerateTradeRoom,
  memberHasElevatedTag,
} from "@/lib/tradeRoomModerationPermission.ts"
import { canManageTradeRoom } from "@/lib/tradeRoomManagementPermission.ts"

export type StageModerationAccess =
  | { ok: true; roomId: string; sectionId: string; targetUserId: string }
  | { ok: false; status: number; error: string }

export async function resolveStageModerationAccess(
  admin: SupabaseClient<Database>,
  options: {
    actorUserId: string
    roomId: string
    sectionId: string
    targetUserId: string
  }
): Promise<StageModerationAccess> {
  const { actorUserId, roomId, sectionId, targetUserId } = options

  if (actorUserId === targetUserId) {
    return { ok: false, status: 400, error: "Cannot change your own stage role." }
  }

  const { data: sectionRow } = await admin
    .from("room_sections")
    .select("id, room_id, live_kind")
    .eq("id", sectionId)
    .eq("room_id", roomId)
    .maybeSingle()

  if (!sectionRow) {
    return { ok: false, status: 404, error: "Channel not found." }
  }

  if ((sectionRow.live_kind ?? "text") !== "voice_stage") {
    return {
      ok: false,
      status: 400,
      error: "Stage actions apply only to stage voice channels.",
    }
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
  const actorHasModTag = tagList.some(
    (t) =>
      actorTagIds.includes(t.id) &&
      t.name.trim().toLowerCase() === "moderator"
  )

  const canManage = canManageTradeRoom({
    viewerId: actorUserId,
    ownerUserId: roomRow.owner_user_id,
    roomKind: roomRow.room_kind,
    isPlatformAdmin: Boolean(adminRow),
  })

  const canModerate = canModerateTradeRoom({
    viewerId: actorUserId,
    ownerUserId: roomRow.owner_user_id,
    hasModeratorTag: actorHasModTag,
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

  const { data: targetMember } = await admin
    .from("room_members")
    .select("left_at")
    .eq("room_id", roomId)
    .eq("user_id", targetUserId)
    .maybeSingle()

  if (!targetMember || targetMember.left_at != null) {
    return {
      ok: false,
      status: 400,
      error: "Target is not an active room member.",
    }
  }

  const { data: targetBan } = await admin
    .from("room_bans")
    .select("user_id")
    .eq("room_id", roomId)
    .eq("user_id", targetUserId)
    .maybeSingle()

  if (targetBan) {
    return { ok: false, status: 400, error: "Target is banned from this room." }
  }

  if (memberHasElevatedTag({ tagIds: targetTagIds, tags: tagList })) {
    // Owners are blocked in canModerateRoomMemberTarget; elevated tags need manage room.
    if (!canManage) {
      return { ok: false, status: 403, error: "Permission denied." }
    }
  }

  return { ok: true, roomId, sectionId, targetUserId }
}
