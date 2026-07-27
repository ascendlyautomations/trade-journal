import { storyReplyPreviewText } from "@/lib/storyReplyMessage"

/** Keep APNs alert bodies readable on the lock screen. */
export const DM_PUSH_PREVIEW_MAX_LENGTH = 100

export function truncatePushPreview(
  text: string,
  maxLength = DM_PUSH_PREVIEW_MAX_LENGTH
): string {
  const trimmed = text.trim()
  if (!trimmed) return ""
  if (trimmed.length <= maxLength) return trimmed
  const slice = trimmed.slice(0, maxLength).trimEnd()
  // Prefer breaking on a word boundary when the cut is mid-word.
  const lastSpace = slice.lastIndexOf(" ")
  const base =
    lastSpace >= Math.floor(maxLength * 0.6) ? slice.slice(0, lastSpace) : slice
  return `${base}…`
}

/**
 * Contextual DM push body. Returns null when the message must not be previewed
 * (deleted / not visible) — callers should skip push entirely.
 */
export function buildDirectMessagePushPreview(message: {
  content?: string | null
  image_url?: string | null
  type?: string | null
  deleted_for_everyone?: boolean | null
  is_system?: boolean | null
}): string | null {
  if (message.deleted_for_everyone) return null
  if (message.is_system) return null

  const type = String(message.type ?? "").trim()

  if (type === "trade") return "Shared a trade"

  if (type === "story_reply") {
    const text = storyReplyPreviewText(message.content, "").trim()
    if (text) return truncatePushPreview(text)
    return "Replied to your story"
  }

  const text = String(message.content ?? "").trim()
  if (text) return truncatePushPreview(text)

  if (message.image_url || type === "image") return "Photo"

  if (type === "post" || type === "profile_post" || type === "achievement_post") {
    return "Shared a post"
  }

  return "New message"
}
