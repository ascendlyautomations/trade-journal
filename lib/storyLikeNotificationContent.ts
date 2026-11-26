export const STORY_LIKE_NOTIFICATION_KIND = "story" as const

export type StoryLikeNotificationContent = {
  kind: typeof STORY_LIKE_NOTIFICATION_KIND
  story_id: string
  story_unavailable?: boolean
}

export function buildStoryLikeNotificationContent(
  storyId: string
): string {
  const payload: StoryLikeNotificationContent = {
    kind: STORY_LIKE_NOTIFICATION_KIND,
    story_id: storyId.trim(),
  }
  return JSON.stringify(payload)
}

export function parseStoryLikeNotificationContent(
  content: string | null | undefined
): StoryLikeNotificationContent | null {
  const trimmed = content?.trim() ?? ""
  if (!trimmed.startsWith("{")) return null
  try {
    const parsed = JSON.parse(trimmed) as StoryLikeNotificationContent
    if (
      parsed?.kind === STORY_LIKE_NOTIFICATION_KIND &&
      typeof parsed.story_id === "string" &&
      parsed.story_id.trim() !== ""
    ) {
      return parsed
    }
  } catch {
    return null
  }
  return null
}