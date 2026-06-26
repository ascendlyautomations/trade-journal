export const STORY_REPLY_MESSAGE_TYPE = "story_reply" as const

export type StoryReplyPayload = {
  text: string
  story_id: string
  story_image_url: string
  story_owner_id: string
  story_owner_username?: string | null
}

export function encodeStoryReplyContent(payload: StoryReplyPayload): string {
  return JSON.stringify(payload)
}

export function decodeStoryReplyContent(
  content: string | null | undefined
): StoryReplyPayload | null {
  if (!content?.trim()) return null
  try {
    const parsed = JSON.parse(content) as Partial<StoryReplyPayload>
    if (
      parsed &&
      typeof parsed === "object" &&
      typeof parsed.story_id === "string" &&
      typeof parsed.story_image_url === "string" &&
      typeof parsed.story_owner_id === "string" &&
      typeof parsed.text === "string"
    ) {
      return parsed as StoryReplyPayload
    }
  } catch {
    /* not JSON */
  }
  return null
}

export function storyReplyPreviewText(
  content: string | null | undefined,
  fallback = "Replied to your story"
): string {
  const payload = decodeStoryReplyContent(content)
  const text = payload?.text?.trim()
  if (text) return text
  return fallback
}
