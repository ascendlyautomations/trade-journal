import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  canModerateTradeRoom,
  memberHasModeratorTag,
  TRADE_ROOM_MODERATOR_TAG_NAME,
} from "@/lib/tradeRoomModerationPermission.ts"
import { canManageTradeRoom } from "@/lib/tradeRoomManagementPermission.ts"

export type RoomSectionLiveKind = "text" | "voice_open" | "voice_stage"

export type LiveVoiceTokenRole = "listener" | "speaker" | "moderator"

export type TradeRoomLiveVoiceAccess =
  | {
      ok: true
      roomId: string
      sectionId: string
      liveKind: "voice_open" | "voice_stage"
      role: LiveVoiceTokenRole
      canPublish: boolean
      canSubscribe: true
      displayName: string | null
      isOwner: boolean
      isModerator: boolean
    }
  | { ok: false; status: number; error: string }

function normalizeLiveKind(raw: string | null | undefined): RoomSectionLiveKind {
  const v = (raw ?? "text").trim().toLowerCase()
  if (v === "voice_open" || v === "voice_stage") return v
  return "text"
}

export async function resolveTradeRoomLiveVoiceAccess(
  admin: SupabaseClient<Database>,
  options: {
    userId: string
    roomId: string
    sectionId: string
  }
): Promise<TradeRoomLiveVoiceAccess> {
  const { userId, roomId, sectionId } = options

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

  const { data: sectionRow, error: sectionErr } = await admin
    .from("room_sections")
    .select("id, room_id, live_kind, allow_members_chat")
    .eq("id", sectionId)
    .eq("room_id", roomId)
    .maybeSingle()

  if (sectionErr) {
    console.error("[livekit/access] section lookup failed", sectionErr.message)
    return { ok: false, status: 500, error: "Could not load channel." }
  }

  if (!sectionRow) {
    return { ok: false, status: 404, error: "Channel not found." }
  }

  const liveKind = normalizeLiveKind(sectionRow.live_kind)
  if (liveKind === "text") {
    return {
      ok: false,
      status: 400,
      error: "This channel does not support live voice.",
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

  const allowMembersChat = sectionRow.allow_members_chat !== false
  const mayPublishByChatPolicy =
    allowMembersChat || canModerate || canManage || isOwner

  let role: LiveVoiceTokenRole = "listener"
  let canPublish = false

  if (liveKind === "voice_open") {
    if (mayPublishByChatPolicy) {
      role = canModerate || canManage ? "moderator" : "speaker"
      canPublish = true
    } else {
      role = "listener"
      canPublish = false
    }
  } else {
    // voice_stage — default listen-only; speakers promoted server-side.
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
    .select("username, display_name")
    .eq("id", userId)
    .maybeSingle()

  const displayName =
    profileRow?.display_name?.trim() ||
    profileRow?.username?.trim() ||
    null

  return {
    ok: true,
    roomId,
    sectionId,
    liveKind,
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
