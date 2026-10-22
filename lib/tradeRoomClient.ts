import type { SupabaseClient } from "@supabase/supabase-js"
import {
  effectiveJoinPolicy,
  normalizedChannelName,
  type TradeRoomCategory,
  type TradeRoomConfiguration,
  type TradeRoomJoinPolicy,
  validateTradeRoomConfiguration,
} from "@/lib/tradeRoomConfiguration"
import { clearRoomSessionsForUser } from "@/lib/roomSessionCache"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

export const TRADE_ROOM_DETAIL_SELECT =
  "id, name, description, slug, image_url, owner_user_id, show_on_profile, is_private, category, discovery_tags, join_policy, rules, members_can_message, members_can_share_trades, members_can_share_media, room_kind, created_at"

export type TradeRoomRow = {
  id: string
  name?: string | null
  description?: string | null
  slug?: string | null
  image_url?: string | null
  owner_user_id?: string | null
  show_on_profile?: boolean | null
  is_private?: boolean | null
  category?: string | null
  discovery_tags?: string[] | null
  join_policy?: string | null
  rules?: string | null
  members_can_message?: boolean | null
  members_can_share_trades?: boolean | null
  members_can_share_media?: boolean | null
  room_kind?: string | null
  created_at?: string | null
}

export type RoomMemberTag = {
  id: string
  room_id: string
  name: string
  color_key: string
  is_preset: boolean | null
}

export type RoomJoinRequest = {
  id: string
  room_id: string
  user_id: string
  status: string
  created_at?: string | null
  profiles?: {
    id?: string
    username?: string | null
    name?: string | null
    avatar_url?: string | null
  } | null
}

function mapRpcCreateError(message: string): string {
  if (message.includes("owned_room_exists")) {
    return "You already have a Trade Room."
  }
  if (message.includes("room_name_required")) return "Room name is required."
  if (message.includes("too_many_discovery_tags")) return "Choose up to 5 tags."
  if (message.includes("too_many_channels")) return "You can have up to 5 sub-rooms."
  if (message.includes("duplicate_channel_name")) {
    return "Sub-room names must be unique."
  }
  return message
}

export async function createTradeRoomViaRpc(
  supabase: SupabaseClient,
  userId: string,
  configuration: TradeRoomConfiguration
): Promise<{ room: TradeRoomRow | null; error: string | null }> {
  const validationError = validateTradeRoomConfiguration(configuration)
  if (validationError) return { room: null, error: validationError }

  const channels = configuration.channels.map((ch) => ({
    name: normalizedChannelName(ch.name),
    allow_members_chat: ch.allowMembersChat,
  }))

  const { data, error } = await supabase.rpc("rpc_v1_create_trade_room", {
    p_name: configuration.name.trim(),
    p_description: configuration.description.trim() || null,
    p_image_url: configuration.imageUrl,
    p_show_on_profile: configuration.showsOnProfile,
    p_is_private: configuration.visibility === "private",
    p_category: configuration.category,
    p_discovery_tags: configuration.discoveryTags,
    p_join_policy: effectiveJoinPolicy(configuration),
    p_rules: configuration.rules.trim() || null,
    p_members_can_message: configuration.membersCanMessage,
    p_members_can_share_trades: configuration.membersCanShareTrades,
    p_members_can_share_media: configuration.membersCanShareMedia,
    p_channels: channels,
  })

  if (error) {
    console.error("[tradeRoom] create RPC:", error)
    return {
      room: null,
      error: mapRpcCreateError(toUserFacingErrorMessage(error)),
    }
  }

  clearRoomSessionsForUser(userId)
  const row = (typeof data === "object" && data !== null ? data : null) as TradeRoomRow | null
  return { room: row, error: null }
}

export type TradeRoomUpdatePayload = {
  name?: string
  description?: string | null
  image_url?: string | null
  show_on_profile?: boolean
  is_private?: boolean
  category?: TradeRoomCategory | null
  discovery_tags?: string[]
  join_policy?: TradeRoomJoinPolicy
  rules?: string | null
  members_can_message?: boolean
  members_can_share_trades?: boolean
  members_can_share_media?: boolean
}

export async function updateTradeRoom(
  supabase: SupabaseClient,
  roomId: string,
  payload: TradeRoomUpdatePayload
): Promise<{ room: TradeRoomRow | null; error: string | null }> {
  const { data, error } = await supabase
    .from("rooms")
    .update(payload)
    .eq("id", roomId)
    .select(TRADE_ROOM_DETAIL_SELECT)
    .single()

  if (error) {
    console.error("[tradeRoom] update:", error)
    return { room: null, error: toUserFacingErrorMessage(error) }
  }
  return { room: data as TradeRoomRow, error: null }
}

export async function deleteTradeRoom(
  supabase: SupabaseClient,
  roomId: string
): Promise<{ error: string | null }> {
  const { error } = await supabase.from("rooms").delete().eq("id", roomId)
  if (error) {
    console.error("[tradeRoom] delete:", error)
    return { error: toUserFacingErrorMessage(error) }
  }
  return { error: null }
}

export async function fetchTradeRoomById(
  supabase: SupabaseClient,
  roomId: string
): Promise<TradeRoomRow | null> {
  const { data, error } = await supabase
    .from("rooms")
    .select(TRADE_ROOM_DETAIL_SELECT)
    .eq("id", roomId)
    .maybeSingle()
  if (error) {
    console.error("[tradeRoom] fetch:", error)
    return null
  }
  return data as TradeRoomRow
}

export async function requestTradeRoomJoin(
  supabase: SupabaseClient,
  roomId: string
): Promise<{ requestId: string | null; status: string | null; error: string | null }> {
  const { data, error } = await supabase.rpc("rpc_v1_request_trade_room_join", {
    p_room_id: roomId,
  })
  if (error) {
    console.error("[tradeRoom] request join:", error)
    return { requestId: null, status: null, error: toUserFacingErrorMessage(error) }
  }
  const row = data as { id?: string; status?: string } | null
  return {
    requestId: row?.id ?? null,
    status: row?.status ?? null,
    error: null,
  }
}

export async function fetchViewerTradeRoomJoinRequest(
  supabase: SupabaseClient,
  roomId: string
): Promise<string | null> {
  const { data, error } = await supabase.rpc("rpc_v1_viewer_trade_room_join_request", {
    p_room_id: roomId,
  })
  if (error) return null
  const row = data as { status?: string } | null
  return row?.status ?? null
}

export async function notifyTradeRoomJoinRequestAfterCreate(
  roomId: string,
  requestId: string
): Promise<void> {
  try {
    await fetch("/api/notifications/trade-room-join-request", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ roomId, requestId }),
    })
  } catch (err) {
    console.error("[tradeRoom] join request notify:", err)
  }
}

export async function listPendingTradeRoomJoinRequests(
  supabase: SupabaseClient,
  roomId: string
): Promise<RoomJoinRequest[]> {
  const { data, error } = await supabase.rpc("rpc_v1_list_trade_room_join_requests", {
    p_room_id: roomId,
    p_status: "pending",
  })
  if (error) {
    console.error("[tradeRoom] list join requests:", error)
    return []
  }
  const payload = data as { requests?: RoomJoinRequest[] } | RoomJoinRequest[] | null
  if (Array.isArray(payload)) return payload
  return payload?.requests ?? []
}

export async function resolveTradeRoomJoinRequest(
  action: "approve" | "decline",
  requestId: string
): Promise<{ ok: boolean; error?: string }> {
  const response = await fetch(`/api/trade-room-join-requests/${action}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ requestId }),
  })
  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as { error?: string }
    return { ok: false, error: body.error ?? "Request failed" }
  }
  return { ok: true }
}

export async function ensureDefaultMemberTags(
  supabase: SupabaseClient,
  roomId: string
): Promise<void> {
  const { error } = await supabase.rpc("ensure_room_member_tags_defaults", {
    p_room_id: roomId,
  })
  if (error) console.error("[tradeRoom] ensure member tags:", error)
}

export async function fetchRoomMemberTags(
  supabase: SupabaseClient,
  roomId: string
): Promise<RoomMemberTag[]> {
  const { data, error } = await supabase
    .from("room_member_tags")
    .select("*")
    .eq("room_id", roomId)
    .order("name")
  if (error) {
    console.error("[tradeRoom] member tags:", error)
    return []
  }
  return (data ?? []) as RoomMemberTag[]
}

export async function createRoomMemberTag(
  supabase: SupabaseClient,
  roomId: string,
  userId: string,
  name: string,
  colorKey: string
): Promise<{ tag: RoomMemberTag | null; error: string | null }> {
  const { data, error } = await supabase
    .from("room_member_tags")
    .insert({
      room_id: roomId,
      name: name.trim(),
      color_key: colorKey,
      is_preset: false,
      created_by: userId,
    })
    .select("*")
    .single()
  if (error) return { tag: null, error: toUserFacingErrorMessage(error) }
  return { tag: data as RoomMemberTag, error: null }
}

export async function updateRoomMemberTag(
  supabase: SupabaseClient,
  tag: Pick<RoomMemberTag, "id" | "room_id" | "name" | "color_key">
): Promise<{ error: string | null }> {
  const { error } = await supabase
    .from("room_member_tags")
    .update({ name: tag.name.trim(), color_key: tag.color_key })
    .eq("id", tag.id)
    .eq("room_id", tag.room_id)
  if (error) return { error: toUserFacingErrorMessage(error) }
  return { error: null }
}

export async function deleteRoomMemberTag(
  supabase: SupabaseClient,
  roomId: string,
  tagId: string
): Promise<{ error: string | null }> {
  const { error } = await supabase
    .from("room_member_tags")
    .delete()
    .eq("id", tagId)
    .eq("room_id", roomId)
  if (error) return { error: toUserFacingErrorMessage(error) }
  return { error: null }
}

export async function fetchMemberTagAssignments(
  supabase: SupabaseClient,
  roomId: string
): Promise<{ user_id: string; tag_id: string }[]> {
  const { data, error } = await supabase
    .from("room_member_tag_assignments")
    .select("user_id, tag_id")
    .eq("room_id", roomId)
  if (error) return []
  return data ?? []
}

export async function assignMemberTag(
  supabase: SupabaseClient,
  roomId: string,
  userId: string,
  tagId: string
): Promise<{ error: string | null }> {
  const { error } = await supabase.from("room_member_tag_assignments").insert({
    room_id: roomId,
    user_id: userId,
    tag_id: tagId,
  })
  if (error && error.code !== "23505") {
    return { error: toUserFacingErrorMessage(error) }
  }
  return { error: null }
}

export async function removeMemberTagAssignment(
  supabase: SupabaseClient,
  roomId: string,
  userId: string,
  tagId: string
): Promise<{ error: string | null }> {
  const { error } = await supabase
    .from("room_member_tag_assignments")
    .delete()
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .eq("tag_id", tagId)
  if (error) return { error: toUserFacingErrorMessage(error) }
  return { error: null }
}

export async function isUserBannedFromRoom(
  supabase: SupabaseClient,
  roomId: string,
  userId: string
): Promise<boolean> {
  const { data, error } = await supabase
    .from("room_bans")
    .select("id")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .maybeSingle()
  if (error) return false
  return data != null
}
