/** Columns required for DM thread rendering (avoids select * on messages). */

const DM_MESSAGE_CORE_COLUMNS = [
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
] as const

/** Includes sender_anonymized when the account-deletion migration is applied. */
export const DM_MESSAGE_CORE_SELECT = [
  ...DM_MESSAGE_CORE_COLUMNS.slice(0, 3),
  "sender_anonymized",
  ...DM_MESSAGE_CORE_COLUMNS.slice(3),
].join(", ")

/** Fallback when `sender_anonymized` is not yet migrated. */
export const DM_MESSAGE_CORE_SELECT_FALLBACK = DM_MESSAGE_CORE_COLUMNS.join(", ")

const PROFILE_EMBED = `
  profiles!sender_id (
    username,
    avatar_url
  )
`

export const DM_MESSAGE_SELECT = `
  ${DM_MESSAGE_CORE_SELECT},
  ${PROFILE_EMBED}
`

export const DM_MESSAGE_SELECT_FALLBACK = `
  ${DM_MESSAGE_CORE_SELECT_FALLBACK},
  ${PROFILE_EMBED}
`

function isMissingSenderAnonymizedColumn(error: {
  code?: string
  message?: string
} | null): boolean {
  if (!error) return false
  if (error.code === "42703" || error.code === "PGRST204") {
    const msg = (error.message ?? "").toLowerCase()
    return msg.includes("sender_anonymized")
  }
  const msg = (error.message ?? "").toLowerCase()
  return msg.includes("sender_anonymized")
}

/** Select DM messages, falling back when sender_anonymized column is absent. */
export async function queryDmMessages<T extends { data: unknown; error: unknown }>(
  run: (select: string) => Promise<T>
): Promise<T> {
  const full = await run(DM_MESSAGE_SELECT)
  if (
    !full.error ||
    !isMissingSenderAnonymizedColumn(
      full.error as { code?: string; message?: string }
    )
  ) {
    return full
  }
  return run(DM_MESSAGE_SELECT_FALLBACK)
}
