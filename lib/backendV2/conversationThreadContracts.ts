import {
  assertContractVersion,
  type BootstrapMetaV1,
} from "./versioning.ts"

export type ConversationThreadParticipantV1 = {
  user_id: string
  profiles: {
    id: string
    username: string | null
    avatar_url: string | null
  } | null
}

export type ConversationThreadMessageV1 = {
  id: string
  conversation_id: string
  sender_id: string | null
  sender_anonymized: boolean
  content: string | null
  created_at: string | null
  seen_by: string[]
  type: string | null
  trade_id: string | null
  post_id: string | null
  profile_post_id: string | null
  achievement_post_id: string | null
  reel_id: string | null
  parent_message_id: string | null
  deleted_for_everyone: boolean
  image_url: string | null
  audio_url: string | null
  audio_duration_ms: number | null
  is_system: boolean
  profiles: { username: string | null; avatar_url: string | null } | null
}

export type ConversationThreadBlockStatusV1 = {
  other_user_id: string
  blocked_by_me: boolean
  blocked_by_other: boolean
} | null

export type ConversationThreadBootstrapV1 = {
  meta: BootstrapMetaV1
  data: {
    conversation: {
      id: string
      is_group: boolean
      name: string | null
      avatar_url: string | null
      is_pinned: boolean
    }
    membership: { is_participant: boolean }
    participants: ConversationThreadParticipantV1[]
    notifications_enabled: boolean
    block_status: ConversationThreadBlockStatusV1
    messages: ConversationThreadMessageV1[]
    has_more_messages: boolean
    next_message_cursor: string | null
    unread_count: number
    mark_read: { applied: boolean }
    notifications_marked_read: number
    page_meta: {
      limit: number
      returned: number
      has_more: boolean
    }
  }
}

export class ConversationThreadContractError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "ConversationThreadContractError"
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

function asStringArray(v: unknown): string[] {
  if (!Array.isArray(v)) return []
  return v.map((x) => String(x))
}

function decodeParticipant(raw: unknown): ConversationThreadParticipantV1 {
  const row = asRecord(raw)
  if (!row) throw new ConversationThreadContractError("participant must be object")
  const userId = asString(row.user_id)
  if (!userId) throw new ConversationThreadContractError("participant.user_id required")
  const profileRaw = asRecord(row.profiles)
  const profiles = profileRaw
    ? {
        id: asString(profileRaw.id) ?? userId,
        username: asString(profileRaw.username),
        avatar_url: asString(profileRaw.avatar_url),
      }
    : null
  return { user_id: userId, profiles }
}

export function decodeConversationThreadMessageV1(
  raw: unknown
): ConversationThreadMessageV1 {
  const row = asRecord(raw)
  if (!row) throw new ConversationThreadContractError("message must be object")
  const id = asString(row.id)
  if (!id) throw new ConversationThreadContractError("message.id required")
  const profileRaw = asRecord(row.profiles)
  return {
    id,
    conversation_id: asString(row.conversation_id) ?? "",
    sender_id: asString(row.sender_id),
    sender_anonymized: asBool(row.sender_anonymized),
    content: row.content == null ? null : String(row.content),
    created_at: asString(row.created_at),
    seen_by: asStringArray(row.seen_by),
    type: asString(row.type),
    trade_id: asString(row.trade_id),
    post_id: asString(row.post_id),
    profile_post_id: asString(row.profile_post_id),
    achievement_post_id: asString(row.achievement_post_id),
    reel_id: asString(row.reel_id),
    parent_message_id: asString(row.parent_message_id),
    deleted_for_everyone: asBool(row.deleted_for_everyone),
    image_url: asString(row.image_url),
    audio_url: asString(row.audio_url),
    audio_duration_ms:
      row.audio_duration_ms == null ? null : asNumber(row.audio_duration_ms, 0),
    is_system: asBool(row.is_system),
    profiles: profileRaw
      ? {
          username: asString(profileRaw.username),
          avatar_url: asString(profileRaw.avatar_url),
        }
      : null,
  }
}

export function decodeConversationThreadBootstrapV1(
  raw: unknown
): ConversationThreadBootstrapV1 {
  const envelope = asRecord(raw)
  if (!envelope) throw new ConversationThreadContractError("envelope required")
  const meta = asRecord(envelope.meta)
  if (!meta) throw new ConversationThreadContractError("meta required")
  assertContractVersion(meta)
  const data = asRecord(envelope.data)
  if (!data) throw new ConversationThreadContractError("data required")

  const convoRaw = asRecord(data.conversation)
  if (!convoRaw?.id) {
    throw new ConversationThreadContractError("conversation.id required")
  }

  const participantsRaw = data.participants
  if (!Array.isArray(participantsRaw)) {
    throw new ConversationThreadContractError("participants must be array")
  }

  const messagesRaw = data.messages
  if (!Array.isArray(messagesRaw)) {
    throw new ConversationThreadContractError("messages must be array")
  }

  const blockRaw = data.block_status
  let blockStatus: ConversationThreadBlockStatusV1 = null
  if (blockRaw != null) {
    const block = asRecord(blockRaw)
    if (block) {
      const otherId = asString(block.other_user_id)
      if (otherId) {
        blockStatus = {
          other_user_id: otherId,
          blocked_by_me: asBool(block.blocked_by_me),
          blocked_by_other: asBool(block.blocked_by_other),
        }
      }
    }
  }

  const pageMetaRaw = asRecord(data.page_meta) ?? {}
  const markReadRaw = asRecord(data.mark_read) ?? {}

  return {
    meta: {
      contract_version: "v1",
      server_time: asString(meta.server_time) ?? "",
      viewer_id: asString(meta.viewer_id),
    },
    data: {
      conversation: {
        id: String(convoRaw.id),
        is_group: asBool(convoRaw.is_group),
        name: asString(convoRaw.name),
        avatar_url: asString(convoRaw.avatar_url),
        is_pinned: asBool(convoRaw.is_pinned),
      },
      membership: {
        is_participant: asBool(asRecord(data.membership)?.is_participant, true),
      },
      participants: participantsRaw.map(decodeParticipant),
      notifications_enabled: asBool(data.notifications_enabled, true),
      block_status: blockStatus,
      messages: messagesRaw.map(decodeConversationThreadMessageV1),
      has_more_messages: asBool(data.has_more_messages),
      next_message_cursor: asString(data.next_message_cursor),
      unread_count: asNumber(data.unread_count),
      mark_read: { applied: asBool(markReadRaw.applied) },
      notifications_marked_read: asNumber(data.notifications_marked_read),
      page_meta: {
        limit: asNumber(pageMetaRaw.limit, 50),
        returned: asNumber(pageMetaRaw.returned, messagesRaw.length),
        has_more: asBool(pageMetaRaw.has_more, asBool(data.has_more_messages)),
      },
    },
  }
}

/** Map RPC message rows to thread page wire shape (PostgREST embed compatible). */
export function mapThreadBootstrapMessagesToWire(
  messages: ConversationThreadMessageV1[]
): unknown[] {
  return messages.map((m) => ({
    id: m.id,
    conversation_id: m.conversation_id,
    sender_id: m.sender_id,
    sender_anonymized: m.sender_anonymized,
    content: m.content,
    created_at: m.created_at,
    seen_by: m.seen_by,
    type: m.type,
    trade_id: m.trade_id,
    post_id: m.post_id,
    profile_post_id: m.profile_post_id,
    achievement_post_id: m.achievement_post_id,
    reel_id: m.reel_id,
    parent_message_id: m.parent_message_id,
    deleted_for_everyone: m.deleted_for_everyone,
    image_url: m.image_url,
    audio_url: m.audio_url,
    audio_duration_ms: m.audio_duration_ms,
    is_system: m.is_system,
    profiles: m.profiles,
  }))
}
