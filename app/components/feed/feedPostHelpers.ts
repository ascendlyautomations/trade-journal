/** Columns used by feed post cards, modal, and share overlay. */
import {
  normalizeFeedAccountType,
  resolveFeedTradeAccountType,
} from "@/lib/feedAccountType"

export { normalizeFeedAccountType, resolveFeedTradeAccountType }

export type FeedScope = "global" | "following"
export type FeedContentFilter = "all" | "trades" | "reels" | "posts" | "achievements"
export type FeedItemKind = "trade" | "profile" | "achievement" | "reel"

export type FeedItem = {
  feedKind: FeedItemKind
  id: string
  user_id: string
  created_at: string
  [key: string]: unknown
}

export const FEED_POSTS_SELECT =
  "id, user_id, trade_id, created_at, pnl, rr, image_url, profiles(username, avatar_url), trades(public_description, user_id, ticker, direction, account_type, points, entry_time, exit_time, entry_price, exit_price, trade_date, duration_seconds, duration_text)"

/** Trade owner for notifications (not always same as post author). */
export function postTradeOwnerUserId(post: {
  user_id?: string | null
  trades?: { user_id?: string | null } | { user_id?: string | null }[] | null
}): string | null {
  const t = post?.trades
  const row = t ? (Array.isArray(t) ? t[0] : t) : null
  const fromTrade = row?.user_id
  if (fromTrade != null && String(fromTrade).trim() !== "") return String(fromTrade)
  const fromPost = post?.user_id
  if (fromPost != null && String(fromPost).trim() !== "") return String(fromPost)
  return null
}

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

export function normalizeAchievementFeedItem(row: Record<string, unknown>): FeedItem {
  return {
    ...row,
    feedKind: "achievement",
    id: String(row.id),
    user_id: String(row.user_id),
    created_at: String(row.created_at),
  }
}

export function normalizeReelFeedItem(row: Record<string, unknown>): FeedItem {
  return {
    ...row,
    feedKind: "reel",
    id: String(row.id),
    user_id: String(row.user_id),
    created_at: String(row.created_at),
  }
}

/** Feed item for reel detail modals (merges profile when list rows omit join). */
export function reelDetailFeedItem(
  reel: Record<string, unknown>,
  owner?: { username?: string | null; avatar_url?: string | null } | null
): FeedItem {
  const hasProfiles =
    reel.profiles != null &&
    typeof reel.profiles === "object" &&
    !Array.isArray(reel.profiles)
  return normalizeReelFeedItem({
    ...reel,
    ...(hasProfiles || !owner
      ? {}
      : {
          profiles: {
            username: owner.username ?? null,
            avatar_url: owner.avatar_url ?? null,
          },
        }),
  })
}

/** Comment section target — content-type agnostic (posts, achievements, reels, …). */
export type FeedCommentTarget = {
  contentId: string
  submitContext: unknown
}

export function feedCommentTarget(
  contentId: string,
  submitContext: unknown
): FeedCommentTarget {
  return { contentId: String(contentId), submitContext }
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

/** Feed comments without reply column (works before reply migration). */
export const FEED_COMMENT_CORE_SELECT =
  "id, post_id, user_id, content, created_at, profiles(username, avatar_url)"

/** Feed comments including reply reference column (no PostgREST parent embed). */
export const FEED_COMMENTS_SELECT =
  `${FEED_COMMENT_CORE_SELECT}, parent_comment_id`

/** Insert return shape — core columns only to avoid PGRST200 / missing-column failures. */
export const FEED_COMMENT_INSERT_SELECT = FEED_COMMENT_CORE_SELECT

function isMissingParentCommentIdColumn(error: {
  code?: string
  message?: string
} | null): boolean {
  if (!error) return false
  if (error.code === "PGRST204") return true
  const msg = (error.message ?? "").toLowerCase()
  return msg.includes("parent_comment_id")
}

/** Select feed comments, falling back when parent_comment_id column is absent. */
export async function queryFeedComments<T extends { data: unknown; error: unknown }>(
  run: (select: string) => Promise<T>
): Promise<T> {
  const full = await run(FEED_COMMENTS_SELECT)
  if (!full.error || !isMissingParentCommentIdColumn(full.error as { code?: string; message?: string })) {
    return full
  }
  return run(FEED_COMMENT_CORE_SELECT)
}

export function withInsertedParentCommentId<T extends Record<string, unknown>>(
  row: T,
  parentCommentId?: string | null
): T & { parent_comment_id?: string | null } {
  if (!parentCommentId) return row
  return { ...row, parent_comment_id: parentCommentId }
}

/** Columns used by the stories bar and viewer. Re-exported from activeStories. */
export { ACTIVE_STORIES_SELECT as FEED_STORIES_SELECT } from "@/lib/activeStories"

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
