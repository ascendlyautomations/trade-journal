import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  canModerateTradeRoom,
  memberHasModeratorTag,
  TRADE_ROOM_MODERATOR_TAG_NAME,
} from "@/lib/tradeRoomModerationPermission.ts"
import { canManageTradeRoom } from "@/lib/tradeRoomManagementPermission.ts"
import {
  normalizeTradeRoomLiveVoiceKind,
  tradeRoomSupportsSharedLiveVoice,
  type TradeRoomLiveVoiceKind,
} from "./tradeRoomSharedLiveVoice.ts"

export type LiveVoiceTokenRole = "listener" | "speaker" | "moderator"

export type TradeRoomLiveVoiceAccess =
  | {
      ok: true
      roomId: string
      liveKind: Extract<TradeRoomLiveVoiceKind, "voice_open" | "voice_stage">
      role: LiveVoiceTokenRole
      canPublish: boolean
      canSubscribe: true
      displayName: string | null
      isOwner: boolean
      isModerator: boolean
    }
  | { ok: false; status: number; error: string }

export async function resolveTradeRoomLiveVoiceAccess(
  admin: SupabaseClient<Database>,
  options: {
    userId: string
    roomId: string
  }
): Promise<TradeRoomLiveVoiceAccess> {
  const { userId, roomId } = options

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
    console.error("[livekit/access] member lookup failed", memberErr.message)
    return { ok: false, status: 500, error: "Could not verify room membership." }
  }

  if (!memberRow || memberRow.left_at != null) {
    return { ok: false, status: 403, error: "Active room membership is required for live voice." }
  }

  const { data: roomRow, error: roomErr } = await admin
    .from("rooms")
    .select("owner_user_id, room_kind, allow_members_chat, live_voice_kind")
    .eq("id", roomId)
    .maybeSingle()

  if (roomErr || !roomRow) {
    return { ok: false, status: 404, error: "Trade Room not found." }
  }

  const liveKind = normalizeTradeRoomLiveVoiceKind(roomRow.live_voice_kind)

  if (!tradeRoomSupportsSharedLiveVoice(liveKind)) {
    return {
      ok: false,
      status: 400,
      error: "Live voice is not enabled for this Trade Room.",
    }
  }

  const voiceKind: Extract<TradeRoomLiveVoiceKind, "voice_open" | "voice_stage"> =
    liveKind === "voice_stage" ? "voice_stage" : "voice_open"

  const { data: adminRow } = await admin
    .from("admin_users")
    .select("user_id")
    .eq("user_id", userId)
    .maybeSingle()

  const { data: tagRows } = await admin
    .from("room_member_tags")
    .select("id, name")
    .eq("room_id", roomId)

  const tags = tagRows ?? []

  const { data: assignmentRows } = await admin
    .from("room_member_tag_assignments")
    .select("tag_id")
    .eq("room_id", roomId)
    .eq("user_id", userId)

  const tagIds = (assignmentRows ?? []).map((r) => r.tag_id)
  const hasModeratorTag = memberHasModeratorTag({ tagIds, tags })
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

  const allowMembersChat = roomRow.allow_members_chat !== false
  const mayPublishByChatPolicy =
    allowMembersChat || canModerate || canManage || isOwner

  let role: LiveVoiceTokenRole = "listener"
  let canPublish = false

  if (voiceKind === "voice_open") {
    if (mayPublishByChatPolicy) {
      role = canModerate || canManage ? "moderator" : "speaker"
      canPublish = true
    } else {
      role = "listener"
      canPublish = false
    }
  } else {
    if (canModerate || canManage) {
      role = "moderator"
      canPublish = true
    } else {
      role = "listener"
      canPublish = false
    }
  }

  const { data: profileRow } = await admin
    .from("profiles")
    .select("username, name")
    .eq("id", userId)
    .maybeSingle()

  const displayName =
    profileRow?.name?.trim() ||
    profileRow?.username?.trim() ||
    null

  return {
    ok: true,
    roomId,
    liveKind: voiceKind,
    role,
    canPublish,
    canSubscribe: true,
    displayName,
    isOwner,
    isModerator: hasModeratorTag || canModerate,
  }
}

export function moderatorTagNamesForDocs(): string {
  return TRADE_ROOM_MODERATOR_TAG_NAME
}
