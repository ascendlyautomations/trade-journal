export const STORY_SHARE_MESSAGE_TYPE = "story_share" as const

export type StorySharePayload = {
  story_id: string
  story_image_url: string
  story_owner_id: string
  story_owner_username?: string | null
}

export type StoryShareMessageLike = {
  type?: string | null
  content?: string | null
}

export function encodeStoryShareContent(payload: StorySharePayload): string {
  return JSON.stringify(payload)
}

export function decodeStoryShareContent(
  content: string | null | undefined
): StorySharePayload | null {
  if (!content?.trim()) return null
  try {
    const parsed = JSON.parse(content) as Partial<StorySharePayload> & { text?: string }
    if (
      parsed &&
      typeof parsed === "object" &&
      typeof parsed.story_id === "string" &&
      typeof parsed.story_image_url === "string" &&
      typeof parsed.story_owner_id === "string" &&
      typeof parsed.text !== "string"
    ) {
      return parsed as StorySharePayload
    }
  } catch {
    /* not JSON */
  }
  return null
}

/** Mirrors native `StoryShareMessageSupport.isStoryShare`. */
export function isStoryShareMessage(message: StoryShareMessageLike): boolean {
  const type = message.type?.trim().toLowerCase()
  if (type === STORY_SHARE_MESSAGE_TYPE) return true
  if (type && type !== "text") return false
  return decodeStoryShareContent(message.content) != null
}

export function resolveStorySharePayload(
  message: StoryShareMessageLike
): StorySharePayload | null {
  if (!isStoryShareMessage(message)) return null
  return decodeStoryShareContent(message.content)
}

export function storyShareCardTitle(payload: StorySharePayload): string {
  const username = payload.story_owner_username?.trim()
  if (username) return `@${username}'s story`
  return "Shared a story"
}

export function storySharePreviewText(
  content: string | null | undefined,
  fallback = "Shared a story"
): string {
  const payload = decodeStoryShareContent(content)
  if (!payload) return fallback
  return storyShareCardTitle(payload)
}

/** Web Messages inbox row — `conversations.last_message` may store raw JSON. */
export function sanitizeConversationListPreview(
  lastMessage: string | null | undefined
): string {
  const trimmed = lastMessage?.trim()
  if (!trimmed) return lastMessage ?? ""
  const payload = decodeStoryShareContent(trimmed)
  if (!payload) return trimmed
  const username = payload.story_owner_username?.trim()
  if (username) return `Shared @${username}'s story`
  return "Shared a story"
}
