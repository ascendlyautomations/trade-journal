import {
  buildFeedDeepLinkHref,
  type ShareContentFeedKind,
} from "@/lib/feedDeepLink"

type PostOwnerLike = {
  id: string
  user_id?: string | null
  profiles?: { username?: string | null } | null
}

/** Opens the trade detail modal on the feed via deep link. */
export function getSharedTradeViewHref(tradeId: string): string {
  const id = String(tradeId ?? "").trim()
  return id ? buildFeedDeepLinkHref({ kind: "trade", id }) : "/feed"
}

/** Opens a feed/profile post detail modal on the feed. */
export function getSharedPostViewHref(post: PostOwnerLike): string {
  const postId = String(post.id ?? "").trim()
  return postId ? buildFeedDeepLinkHref({ kind: "post", id: postId }) : "/feed"
}

/** Opens an achievement detail modal on the feed. */
export function getSharedAchievementViewHref(post: PostOwnerLike): string {
  const postId = String(post.id ?? "").trim()
  return postId
    ? buildFeedDeepLinkHref({ kind: "achievement", id: postId })
    : "/feed"
}

/** Opens a reel detail modal on the feed. */
export function getSharedReelViewHref(post: PostOwnerLike): string {
  const reelId = String(post.id ?? "").trim()
  return reelId ? buildFeedDeepLinkHref({ kind: "reel", id: reelId }) : "/feed"
}

export function getSharedContentViewHref(
  post: PostOwnerLike & {
    achievements?: unknown
    achievement_id?: string | null
    feedKind?: ShareContentFeedKind | string | null
    video_url?: string | null
  }
): string {
  if (post.feedKind === "reel" || post.video_url) {
    return getSharedReelViewHref(post)
  }
  if (
    post.feedKind === "achievement" ||
    post.achievements != null ||
    post.achievement_id
  ) {
    return getSharedAchievementViewHref(post)
  }
  return getSharedPostViewHref(post)
}

export const SHARED_TRADE_UNAVAILABLE =
  "This trade is no longer available."

export const SHARED_POST_UNAVAILABLE =
  "This post is no longer available."
