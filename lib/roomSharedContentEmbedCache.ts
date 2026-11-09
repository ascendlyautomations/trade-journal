/**
 * In-memory cache for Trade Room / DM shared embeds (posts, reels, etc.)
 * so parent re-renders (typing, voice state) don't reset loading state or refetch.
 */
import type { RoomSharedContentReference } from "@/lib/roomMessageSharedContent"

export function stableRoomSharedContentKey(
  ref: RoomSharedContentReference
): string {
  switch (ref.kind) {
    case "post":
      return `post:${ref.postId ?? ""}`
    case "profile_post":
      return `profile_post:${ref.profilePostId ?? ""}`
    case "achievement_post":
      return `achievement_post:${ref.achievementPostId ?? ""}`
    case "reel":
      return `reel:${ref.reelId ?? ""}`
    case "trade":
      return `trade:${ref.tradeId ?? ""}`
    default:
      return `unknown:${ref.kind}`
  }
}

type CachedRow<T> = { data: T; fetchedAt: number }

const postEmbedCache = new Map<string, CachedRow<unknown>>()
const postEmbedInflight = new Map<string, Promise<unknown>>()

/** `undefined` = cache miss; `null` = fetched successfully but row missing. */
export function getCachedRoomSharedPostEmbed<T = unknown>(
  key: string
): T | null | undefined {
  const row = postEmbedCache.get(key)
  if (!row) return undefined
  return row.data as T
}

export function setCachedRoomSharedPostEmbed<T = unknown>(
  key: string,
  data: T
): void {
  postEmbedCache.set(key, { data, fetchedAt: Date.now() })
}

export function getOrCreateRoomSharedPostInflight(
  key: string,
  factory: () => Promise<unknown>
): Promise<unknown> {
  const existing = postEmbedInflight.get(key)
  if (existing) return existing
  const p = factory().finally(() => {
    postEmbedInflight.delete(key)
  })
  postEmbedInflight.set(key, p)
  return p
}

/** Optional: cap cache size in a future iteration; keep generous for session UX. */
const TRADE_EMBED_CACHE_MAX = 80

type TradeCacheRow = { data: unknown; fetchedAt: number; viewerKey: string }

const tradeEmbedCache = new Map<string, TradeCacheRow>()
const tradeEmbedInflight = new Map<string, Promise<unknown>>()

export function tradeEmbedCacheKey(
  tradeId: string,
  viewerUserId: string | null | undefined
): string {
  const v = viewerUserId?.trim() || "__anon__"
  return `trade:${tradeId.trim()}:${v}`
}

/** `undefined` = miss; cached loaded row including `null` when unavailable after fetch. */
export function getCachedSharedTradeEmbed<T = unknown>(
  key: string
): T | null | undefined {
  const row = tradeEmbedCache.get(key)
  if (!row) return undefined
  return row.data as T
}

export function setCachedSharedTradeEmbed<T = unknown>(
  key: string,
  data: T,
  viewerKey: string
): void {
  if (tradeEmbedCache.size >= TRADE_EMBED_CACHE_MAX) {
    const oldest = tradeEmbedCache.keys().next().value as string | undefined
    if (oldest) tradeEmbedCache.delete(oldest)
  }
  tradeEmbedCache.set(key, { data, fetchedAt: Date.now(), viewerKey })
}

export function getOrCreateSharedTradeInflight(
  key: string,
  factory: () => Promise<unknown>
): Promise<unknown> {
  const existing = tradeEmbedInflight.get(key)
  if (existing) return existing
  const p = factory().finally(() => {
    tradeEmbedInflight.delete(key)
  })
  tradeEmbedInflight.set(key, p)
  return p
}
