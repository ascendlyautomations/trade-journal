import { feedContentOwnerUserId } from "@/app/components/feed/feedPostHelpers"

/** True when this feed row is authored by the current viewer (must not appear in their Feed). */
export function isViewerOwnFeedItem(
  post: unknown,
  viewerUserId: string | null | undefined
): boolean {
  if (!viewerUserId) return false
  const owner = feedContentOwnerUserId(post)
  return owner != null && owner === viewerUserId
}

export function excludeViewerOwnFeedItems<T>(
  posts: T[],
  viewerUserId: string | null | undefined
): T[] {
  if (!viewerUserId) return posts
  return posts.filter((row) => !isViewerOwnFeedItem(row, viewerUserId))
}
