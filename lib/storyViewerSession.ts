/** In-session story views (supplements durable `story_views` / `viewer_has_seen`). */

const viewedStoryIds = new Set<string>()

export function markStoryViewedInSession(storyId: string) {
  const id = String(storyId ?? "").trim()
  if (!id) return
  viewedStoryIds.add(id)
}

export function isStoryViewedInSession(storyId: string): boolean {
  return viewedStoryIds.has(String(storyId ?? "").trim())
}

export function getStoryViewerSessionSeen(): ReadonlySet<string> {
  return viewedStoryIds
}

export function clearStoryViewerSession() {
  viewedStoryIds.clear()
}