/**
 * PostgREST select shape for room_messages with embedded reactions.
 *
 * Explicit embed hint avoids PGRST201 when multiple FKs exist and keeps
 * queries stable if a redundant FK is ever reintroduced.
 */
export const ROOM_MESSAGE_REACTIONS_FKEY =
  "room_message_reactions_message_room_fkey"

export const ROOM_MESSAGE_REACTIONS_EMBED = `room_message_reactions!${ROOM_MESSAGE_REACTIONS_FKEY}`

export const ROOM_MESSAGE_SELECT_SHAPE = `
  id,
  room_id,
  user_id,
  seen_by,
  pinned,
  section_id,
  parent_message_id,
  type,
  trade_id,
  content,
  image_url,
  audio_url,
  audio_duration_ms,
  created_at,
  trades!room_messages_trade_id_fkey (
    id
  ),
  profiles (
    username,
    avatar_url
  ),
  ${ROOM_MESSAGE_REACTIONS_EMBED} (
    id,
    message_id,
    user_id,
    reaction
  )
`.trim()

/** Compact shape for legacy repository loaders. */
export const ROOM_MESSAGE_SELECT_COMPACT = `
  id,
  room_id,
  user_id,
  seen_by,
  pinned,
  section_id,
  parent_message_id,
  type,
  trade_id,
  content,
  image_url,
  audio_url,
  audio_duration_ms,
  created_at,
  trades!room_messages_trade_id_fkey ( id ),
  profiles ( username, avatar_url ),
  ${ROOM_MESSAGE_REACTIONS_EMBED} ( id, message_id, user_id, reaction )
`.trim()

/** Runtime-validated room_messages row for ROOM_MESSAGE_SELECT_SHAPE queries. */
export type RoomMessageProjectedRow = Record<string, unknown> & {
  id: string
}
