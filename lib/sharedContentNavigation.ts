import { profilePath } from "@/lib/profileRoutes"

type PostOwnerLike = {
  id: string
  user_id?: string | null
  profiles?: { username?: string | null } | null
}

/** Canonical public trade page (handles unavailable/private gracefully). */
export function getSharedTradeViewHref(tradeId: string): string {
  const id = String(tradeId ?? "").trim()
  return id ? `/trade/${encodeURIComponent(id)}` : "/feed"
}

/**
 * Profile deep-link for feed posts — reuses notification/profile `?post=` handling.
 */
export function getSharedPostViewHref(post: PostOwnerLike): string {
  const postId = String(post.id ?? "").trim()
  const ownerId = post.user_id != null ? String(post.user_id).trim() : ""

  const base = profilePath({
    id: ownerId,
    username: post.profiles?.username,
  })

  if (!postId) return base

  const params = new URLSearchParams({ post: postId })
  return `${base}?${params.toString()}`
}

/** Profile achievements tab deep-link for shared achievement posts. */
export function getSharedAchievementViewHref(post: PostOwnerLike): string {
  const postId = String(post.id ?? "").trim()
  const ownerId = post.user_id != null ? String(post.user_id).trim() : ""

  const base = profilePath({
    id: ownerId,
    username: post.profiles?.username,
  })

  if (!postId) return `${base}?tab=achievements`

  const params = new URLSearchParams({
    achievement: postId,
    tab: "achievements",
  })
  return `${base}?${params.toString()}`
}

/** Profile reels tab deep-link. */
export function getSharedReelViewHref(post: PostOwnerLike): string {
  const reelId = String(post.id ?? "").trim()
  const ownerId = post.user_id != null ? String(post.user_id).trim() : ""

  const base = profilePath({
    id: ownerId,
    username: post.profiles?.username,
  })

  if (!reelId) return `${base}?tab=reels`

  const params = new URLSearchParams({
    reel: reelId,
    tab: "reels",
  })
  return `${base}?${params.toString()}`
}

export function getSharedContentViewHref(
  post: PostOwnerLike & {
    achievements?: unknown
    achievement_id?: string | null
    feedKind?: string | null
    video_url?: string | null
  }
): string {
  if (post.feedKind === "reel" || post.video_url) {
    return getSharedReelViewHref(post)
  }
  if (post.achievements != null || post.achievement_id) {
    return getSharedAchievementViewHref(post)
  }
  return getSharedPostViewHref(post)
}

export const SHARED_TRADE_UNAVAILABLE =
  "This trade is no longer available."

export const SHARED_POST_UNAVAILABLE =
  "This post is no longer available."
