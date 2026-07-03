/** Columns required for DM thread rendering (avoids select * on messages). */
export const DM_MESSAGE_CORE_SELECT = [
  "id",
  "conversation_id",
  "sender_id",
  "content",
  "created_at",
  "seen_by",
  "type",
  "trade_id",
  "post_id",
  "profile_post_id",
  "achievement_post_id",
  "reel_id",
  "parent_message_id",
  "deleted_for_everyone",
  "image_url",
  "is_system",
].join(", ")

export const DM_MESSAGE_SELECT = `
  ${DM_MESSAGE_CORE_SELECT},
  profiles!sender_id (
    username,
    avatar_url
  )
`
