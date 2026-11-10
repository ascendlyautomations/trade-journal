import type { FeedContentFilter } from "@/app/components/feed/feedPostHelpers"

/** Order matches `FeedContentToggle` and native `FeedContentFilter`. */
export const FEED_CONTENT_FILTER_ORDER: FeedContentFilter[] = [
  "all",
  "trades",
  "reels",
  "posts",
  "achievements",
]

export const FEED_FILTER_SWIPE_MIN_DISTANCE_PX = 28
export const FEED_FILTER_SWIPE_DIRECTION_THRESHOLD_PX = 56
export const FEED_FILTER_SWIPE_HORIZONTAL_RATIO = 1.35

export function adjacentFeedContentFilter(
  current: FeedContentFilter,
  offset: number
): FeedContentFilter | null {
  const index = FEED_CONTENT_FILTER_ORDER.indexOf(current)
  if (index < 0) return null
  const next = index + offset
  if (next < 0 || next >= FEED_CONTENT_FILTER_ORDER.length) return null
  return FEED_CONTENT_FILTER_ORDER[next]!
}

export function resolveFeedContentFilterSwipe(
  startX: number,
  startY: number,
  endX: number,
  endY: number,
  current: FeedContentFilter
): FeedContentFilter | null {
  const dx = endX - startX
  const dy = endY - startY
  const absX = Math.abs(dx)
  const absY = Math.abs(dy)
  if (Math.max(absX, absY) < FEED_FILTER_SWIPE_DIRECTION_THRESHOLD_PX) return null
  if (absX <= absY * FEED_FILTER_SWIPE_HORIZONTAL_RATIO) return null
  if (startX < 24 && dx > 0) return null
  if (dx < 0) return adjacentFeedContentFilter(current, 1)
  return adjacentFeedContentFilter(current, -1)
}
