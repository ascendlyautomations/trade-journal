import {
  assertContractVersion,
  type BootstrapMetaV1,
} from "./versioning.ts"

export type RoomSectionV1 = {
  id: string
  room_id: string
  name: string
  position: number
  allow_members_chat: boolean
}

export type RoomMessageReactionV1 = {
  id: string
  message_id: string
  user_id: string
  reaction: string
}

export type RoomMessageV1 = {
  id: string
  room_id: string
  user_id: string
  seen_by: unknown
  pinned: boolean
  section_id: string | null
  parent_message_id: string | null
  type: string | null
  trade_id: string | null
  content: string | null
  image_url: string | null
  audio_url: string | null
  audio_duration_ms: number | null
  created_at: string | null
  trades?: { id: string } | null
  profiles?: { username: string | null; avatar_url: string | null } | null
  room_message_reactions?: RoomMessageReactionV1[]
}

export type RoomBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    room: {
      id: string
      name: string | null
      description?: string | null
      slug: string | null
      image_url: string | null
      owner_user_id: string | null
      /** Wire-compat only — rooms table has no is_public; defaults true. */
      is_public: boolean
      /** Wire-compat only — chat permission is per section; defaults true. */
      allow_members_chat: boolean
      show_on_profile: boolean
      created_at: string | null
    }
    membership: {
      notification_enabled: boolean
      is_owner: boolean
    }
    sections: RoomSectionV1[]
    active_section_id: string | null
    channel_preferences: Record<string, boolean>
    member_stats: {
      total_members: number
      active_members: number
      left_members: number
    } | null
    unread_count: number
    mark_read: { applied: boolean }
    pinned_messages: RoomMessageV1[]
    messages: RoomMessageV1[]
    has_more_messages: boolean
    next_message_cursor: string | null
  }
}

function asRecord(v: unknown): Record<string, unknown> | null {
  return v != null && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : null
}

function asString(v: unknown): string | null {
  if (v == null) return null
  const s = String(v).trim()
  return s.length > 0 ? s : null
}

function asBool(v: unknown, fallback = false): boolean {
  if (typeof v === "boolean") return v
  if (v === "true") return true
  if (v === "false") return false
  return fallback
}

function asNumber(v: unknown, fallback = 0): number {
  const n = Number(v)
  return Number.isFinite(n) ? n : fallback
}

function decodeReaction(raw: unknown): RoomMessageReactionV1 {
  const r = asRecord(raw) ?? {}
  return {
    id: String(r.id ?? ""),
    message_id: String(r.message_id ?? ""),
    user_id: String(r.user_id ?? ""),
    reaction: String(r.reaction ?? ""),
  }
}

export function decodeRoomMessageV1(raw: unknown): RoomMessageV1 {
  const r = asRecord(raw) ?? {}
  const trades = asRecord(r.trades)
  const profiles = asRecord(r.profiles)
  const reactions = Array.isArray(r.room_message_reactions)
    ? r.room_message_reactions.map(decodeReaction)
    : []
  return {
    id: String(r.id ?? ""),
    room_id: String(r.room_id ?? ""),
    user_id: String(r.user_id ?? ""),
    seen_by: r.seen_by ?? [],
    pinned: asBool(r.pinned),
    section_id: asString(r.section_id),
    parent_message_id: asString(r.parent_message_id),
    type: asString(r.type),
    trade_id: asString(r.trade_id),
    content: asString(r.content),
    image_url: asString(r.image_url),
    audio_url: asString(r.audio_url),
    audio_duration_ms:
      r.audio_duration_ms == null ? null : asNumber(r.audio_duration_ms, 0),
    created_at: asString(r.created_at),
    trades: trades?.id ? { id: String(trades.id) } : null,
    profiles: profiles
      ? {
          username: asString(profiles.username),
          avatar_url: asString(profiles.avatar_url),
        }
      : null,
    room_message_reactions: reactions,
  }
}

export class RoomBootstrapContractError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "RoomBootstrapContractError"
  }
}

function decodeSection(raw: unknown): RoomSectionV1 {
  const r = asRecord(raw) ?? {}
  return {
    id: String(r.id ?? ""),
    room_id: String(r.room_id ?? ""),
    name: String(r.name ?? ""),
    position: asNumber(r.position),
    allow_members_chat: asBool(r.allow_members_chat, true),
  }
}

export function decodeRoomBootstrapV1(raw: unknown): RoomBootstrapV1 {
  const root = asRecord(raw) ?? {}
  const meta = asRecord(root.meta) ?? {}
  const data = asRecord(root.data) ?? {}
  const room = asRecord(data.room) ?? {}
  const membership = asRecord(data.membership) ?? {}
  const memberStats = asRecord(data.member_stats)
  const markRead = asRecord(data.mark_read) ?? {}
  const channelPrefsRaw = asRecord(data.channel_preferences) ?? data.channel_preferences
  const channelPrefs: Record<string, boolean> = {}
  if (channelPrefsRaw && typeof channelPrefsRaw === "object") {
    for (const [k, v] of Object.entries(channelPrefsRaw as Record<string, unknown>)) {
      channelPrefs[k] = asBool(v, true)
    }
  }

  assertContractVersion(meta)

  if (!Array.isArray(data.pinned_messages)) {
    throw new RoomBootstrapContractError(
      "room bootstrap data.pinned_messages must be an array"
    )
  }
  if (!Array.isArray(data.messages)) {
    throw new RoomBootstrapContractError(
      "room bootstrap data.messages must be an array"
    )
  }
  if (!Array.isArray(data.sections)) {
    throw new RoomBootstrapContractError(
      "room bootstrap data.sections must be an array"
    )
  }

  return {
    meta: {
      contract_version: "v1",
      server_time: String(meta.server_time ?? ""),
      viewer_id: asString(meta.viewer_id),
    },
    data: {
      room: {
        id: String(room.id ?? ""),
        name: asString(room.name),
        description: asString(room.description),
        slug: asString(room.slug),
        image_url: asString(room.image_url),
        owner_user_id: asString(room.owner_user_id),
        is_public: asBool(room.is_public, true),
        allow_members_chat: asBool(room.allow_members_chat, true),
        show_on_profile: asBool(room.show_on_profile, true),
        created_at: asString(room.created_at),
      },
      membership: {
        notification_enabled: asBool(membership.notification_enabled, true),
        is_owner: asBool(membership.is_owner),
      },
      sections: data.sections.map(decodeSection),
      active_section_id: asString(data.active_section_id),
      channel_preferences: channelPrefs,
      member_stats: memberStats
        ? {
            total_members: asNumber(memberStats.total_members),
            active_members: asNumber(memberStats.active_members),
            left_members: asNumber(memberStats.left_members),
          }
        : null,
      unread_count: asNumber(data.unread_count),
      mark_read: { applied: asBool(markRead.applied) },
      pinned_messages: data.pinned_messages.map(decodeRoomMessageV1),
      messages: data.messages.map(decodeRoomMessageV1),
      has_more_messages: asBool(data.has_more_messages),
      next_message_cursor: asString(data.next_message_cursor),
    },
  }
}
