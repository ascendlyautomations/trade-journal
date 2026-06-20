/** Columns used by feed post cards, modal, and share overlay. */
import {
  normalizeFeedAccountType,
  resolveFeedTradeAccountType,
} from "@/lib/feedAccountType"

export { normalizeFeedAccountType, resolveFeedTradeAccountType }

export type FeedScope = "global" | "following"
export type FeedContentFilter = "all" | "trades" | "posts"
export type FeedItemKind = "trade" | "profile"

export type FeedItem = {
  feedKind: FeedItemKind
  id: string
  user_id: string
  created_at: string
  [key: string]: unknown
}

export const FEED_POSTS_SELECT =
  "id, user_id, trade_id, created_at, pnl, rr, image_url, profiles(username, avatar_url), trades(public_description, user_id, ticker, direction, account_type, points, entry_time, exit_time, entry_price, exit_price, trade_date, duration_seconds, duration_text)"

export function normalizeTradeFeedItem(row: Record<string, unknown>): FeedItem {
  return {
    ...row,
    feedKind: "trade",
    id: String(row.id),
    user_id: String(row.user_id),
    created_at: String(row.created_at),
  }
}

export function normalizeProfileFeedItem(row: Record<string, unknown>): FeedItem {
  return {
    ...row,
    feedKind: "profile",
    id: String(row.id),
    user_id: String(row.user_id),
    created_at: String(row.created_at),
  }
}

export function sortFeedItemsDesc(items: FeedItem[]): FeedItem[] {
  return [...items].sort(
    (a, b) =>
      new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  )
}

export function dedupeFeedItems(items: FeedItem[]): FeedItem[] {
  const seen = new Set<string>()
  const out: FeedItem[] = []

  for (const item of items) {
    const key = `${item.feedKind}:${item.id}`
    if (seen.has(key)) continue
    seen.add(key)
    out.push(item)
  }

  return out
}

/** Columns used by feed comment threads. */
export const FEED_COMMENTS_SELECT =
  "id, post_id, user_id, content, created_at, profiles(username, avatar_url)"

/** Returned row shape after posting a comment. */
export const FEED_COMMENT_INSERT_SELECT =
  "id, post_id, user_id, content, created_at, profiles(username, avatar_url)"

/** Columns used by the stories bar and viewer. */
export const FEED_STORIES_SELECT = "id, user_id, image_url, created_at"

export function postImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http") || raw.startsWith("blob:")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

export function postPublicDescription(post: any): string | null {
  const t = post?.trades
  if (!t) return null
  const row = Array.isArray(t) ? t[0] : t
  const raw = row?.public_description
  if (raw == null) return null
  const s = String(raw).trim()
  return s !== "" ? s : null
}

export function postTradeJoin(post: any) {
  const t = post?.trades
  if (!t) return null
  return Array.isArray(t) ? t[0] : t
}

export function getModeStyles(mode: string | null | undefined): string {
  if (!mode) return ""
  const m = mode.toLowerCase()
  if (m === "funded") return "bg-green-500/20 text-green-300"
  if (m === "eval") return "bg-yellow-500/20 text-yellow-300"
  if (m === "live") return "bg-blue-500/20 text-blue-300"
  return "bg-white/10 text-gray-300"
}

/** Deduped feed posts plus id lookup in a single pass. */
export function buildFeedPostsIndex(posts: any[]): {
  postsById: Map<string, any>
  uniquePosts: any[]
} {
  const postsById = new Map<string, any>()
  for (const p of posts) {
    postsById.set(String(p.id), p)
  }
  return {
    postsById,
    uniquePosts: Array.from(postsById.values()),
  }
}
