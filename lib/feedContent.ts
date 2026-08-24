import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "./demo/constants"
import { mapProjectedRows } from "./supabaseProjectedQuery"
import { isDemoModeActive } from "./demo/demoMode"
import {
  fetchDemoFeedBatch,
  findDemoFeedItem,
  findDemoFeedItemByTradeId,
  getDemoFollowingIds,
  topUpDemoMergedFeedBuffer,
} from "./demo/demoFeed"
import {
  FEED_ACHIEVEMENT_POSTS_SELECT,
} from "@/lib/achievementPostEngagement"
import { FEED_REELS_SELECT } from "@/lib/reelEngagement"
import { fetchReelsByTradeIds } from "@/lib/reels"
import {
  FEED_POSTS_SELECT,
  type FeedContentFilter,
  type FeedItem,
  type FeedScope,
  dedupeFeedItems,
  normalizeAchievementFeedItem,
  normalizeProfileFeedItem,
  normalizeReelFeedItem,
  normalizeTradeFeedItem,
  postAttachedReel,
  postTradeJoin,
  sortFeedItemsDesc,
} from "@/app/components/feed/feedPostHelpers"

export const FEED_PAGE_SIZE = 8

export const FEED_PROFILE_POSTS_SELECT =
  "id, user_id, content, image_url, created_at, room_id, room_name, room_logo, room_description, profiles(username, avatar_url)"

export async function fetchFollowingIds(
  supabase: SupabaseClient,
  userId: string
): Promise<string[]> {
  if (isDemoUserId(userId)) {
    return getDemoFollowingIds(userId)
  }

  const { data, error } = await supabase
    .from("followers")
    .select("following_id")
    .eq("follower_id", userId)

  if (error) throw error
  return (data ?? []).map((row) => String(row.following_id))
}

type FeedBatchResult = {
  items: FeedItem[]
  emptyFollowing?: boolean
}

function applyScopeFilter<T extends { neq: Function; in: Function; not: Function }>(
  query: T,
  scope: FeedScope,
  userId: string,
  followingIds: string[]
): T | null {
  let scoped = query.neq("user_id", userId) as T

  if (scope === "following") {
    if (followingIds.length === 0) return null
    scoped = scoped.in("user_id", followingIds) as T
    return scoped
  }

  if (followingIds.length > 0) {
    scoped = scoped.not("user_id", "in", `(${followingIds.join(",")})`) as T
  }

  return scoped
}

async function hydrateTradeFeedItemsWithReels(
  supabase: SupabaseClient,
  viewerId: string,
  items: FeedItem[]
): Promise<FeedItem[]> {
  const tradeIds = items
    .filter((item) => item.feedKind === "trade" && !postAttachedReel(item))
    .map((item) =>
      item.trade_id != null ? String(item.trade_id) : String(item.id)
    )
    .filter((id) => id.trim() !== "")

  if (tradeIds.length === 0) return items

  const reelMap = await fetchReelsByTradeIds(supabase, viewerId, tradeIds)
  if (reelMap.size === 0) return items

  return items.map((item) => {
    if (item.feedKind !== "trade" || postAttachedReel(item)) return item
    const tradeId =
      item.trade_id != null ? String(item.trade_id) : String(item.id)
    const reel = reelMap.get(tradeId)
    if (!reel) return item

    const trade = postTradeJoin(item)
    if (!trade) return item

    return {
      ...item,
      trades: { ...trade, reels: reel },
    }
  })
}

export async function fetchTradeFeedBatch(
  supabase: SupabaseClient,
  options: {
    scope: FeedScope
    userId: string
    followingIds: string[]
    page: number
    pageSize?: number
  }
): Promise<FeedBatchResult> {
  if (isDemoUserId(options.userId)) {
    return fetchDemoFeedBatch({ ...options, kind: "trade" })
  }

  const pageSize = options.pageSize ?? FEED_PAGE_SIZE
  const from = options.page * pageSize
  const to = from + pageSize - 1

  if (options.scope === "following" && options.followingIds.length === 0) {
    return { items: [], emptyFollowing: true }
  }

  const baseQuery = supabase
    .from("posts")
    .select(FEED_POSTS_SELECT)
    .order("created_at", { ascending: false })
    .range(from, to)

  const scoped = applyScopeFilter(
    baseQuery,
    options.scope,
    options.userId,
    options.followingIds
  )

  if (!scoped) {
    return { items: [], emptyFollowing: true }
  }

  const { data, error } = await scoped.overrideTypes<
    Record<string, unknown>[],
    { merge: false }
  >()

  let rows = data

  if (error) {
    const fallbackSelect = FEED_POSTS_SELECT.replace(
      /, reels\([^)]+\)/,
      ""
    )
    const retry = supabase
      .from("posts")
      .select(fallbackSelect)
      .order("created_at", { ascending: false })
      .range(from, to)
    const retryScoped = applyScopeFilter(
      retry,
      options.scope,
      options.userId,
      options.followingIds
    )
    if (!retryScoped) {
      return { items: [], emptyFollowing: true }
    }
    const retryResult = await retryScoped.overrideTypes<
      Record<string, unknown>[],
      { merge: false }
    >()
    if (retryResult.error) throw retryResult.error
    rows = retryResult.data
  }

  let items = mapProjectedRows(rows, normalizeTradeFeedItem)

  if (
    items.some(
      (item) => item.feedKind === "trade" && !postAttachedReel(item)
    )
  ) {
    items = await hydrateTradeFeedItemsWithReels(supabase, options.userId, items)
  }

  return { items }
}

export async function fetchProfileFeedBatch(
  supabase: SupabaseClient,
  options: {
    scope: FeedScope
    userId: string
    followingIds: string[]
    page: number
    pageSize?: number
  }
): Promise<FeedBatchResult> {
  if (isDemoUserId(options.userId)) {
    return fetchDemoFeedBatch({ ...options, kind: "profile" })
  }

  const pageSize = options.pageSize ?? FEED_PAGE_SIZE
  const from = options.page * pageSize
  const to = from + pageSize - 1

  if (options.scope === "following" && options.followingIds.length === 0) {
    return { items: [], emptyFollowing: true }
  }

  const baseQuery = supabase
    .from("profile_posts")
    .select(FEED_PROFILE_POSTS_SELECT)
    .order("created_at", { ascending: false })
    .range(from, to)

  const scoped = applyScopeFilter(
    baseQuery,
    options.scope,
    options.userId,
    options.followingIds
  )

  if (!scoped) {
    return { items: [], emptyFollowing: true }
  }

  const { data, error } = await scoped.overrideTypes<
    Record<string, unknown>[],
    { merge: false }
  >()
  if (error) throw error

  return {
    items: mapProjectedRows(data, normalizeProfileFeedItem),
  }
}

export async function fetchAchievementFeedBatch(
  supabase: SupabaseClient,
  options: {
    scope: FeedScope
    userId: string
    followingIds: string[]
    page: number
    pageSize?: number
  }
): Promise<FeedBatchResult> {
  if (isDemoUserId(options.userId)) {
    return fetchDemoFeedBatch({ ...options, kind: "achievement" })
  }

  const pageSize = options.pageSize ?? FEED_PAGE_SIZE
  const from = options.page * pageSize
  const to = from + pageSize - 1

  if (options.scope === "following" && options.followingIds.length === 0) {
    return { items: [], emptyFollowing: true }
  }

  const baseQuery = supabase
    .from("achievement_posts")
    .select(FEED_ACHIEVEMENT_POSTS_SELECT)
    .eq("achievements.is_public", true)
    .order("created_at", { ascending: false })
    .range(from, to)

  const scoped = applyScopeFilter(
    baseQuery,
    options.scope,
    options.userId,
    options.followingIds
  )

  if (!scoped) {
    return { items: [], emptyFollowing: true }
  }

  const { data, error } = await scoped.overrideTypes<
    Record<string, unknown>[],
    { merge: false }
  >()
  if (error) throw error

  return {
    items: mapProjectedRows(data, normalizeAchievementFeedItem),
  }
}

export async function fetchReelFeedBatch(
  supabase: SupabaseClient,
  options: {
    scope: FeedScope
    userId: string
    followingIds: string[]
    page: number
    pageSize?: number
  }
): Promise<FeedBatchResult> {
  if (isDemoUserId(options.userId)) {
    return fetchDemoFeedBatch({ ...options, kind: "reel" })
  }

  const pageSize = options.pageSize ?? FEED_PAGE_SIZE
  const from = options.page * pageSize
  const to = from + pageSize - 1

  if (options.scope === "following" && options.followingIds.length === 0) {
    return { items: [], emptyFollowing: true }
  }

  const baseQuery = supabase
    .from("reels")
    .select(FEED_REELS_SELECT)
    .order("created_at", { ascending: false })
    .range(from, to)

  const scoped = applyScopeFilter(
    baseQuery,
    options.scope,
    options.userId,
    options.followingIds
  )

  if (!scoped) {
    return { items: [], emptyFollowing: true }
  }

  const { data, error } = await scoped.overrideTypes<
    Record<string, unknown>[],
    { merge: false }
  >()
  if (error) throw error

  return {
    items: mapProjectedRows(data, normalizeReelFeedItem),
  }
}

export async function fetchTradeFeedPostById(
  supabase: SupabaseClient,
  postId: string
): Promise<FeedItem | null> {
  const demo = findDemoFeedItem(postId, "trade")
  if (demo) return demo
  if (isDemoModeActive()) return null

  const { data, error } = await supabase
    .from("posts")
    .select(FEED_POSTS_SELECT)
    .eq("id", postId)
    .maybeSingle()
    .overrideTypes<Record<string, unknown> | null, { merge: false }>()

  if (error) {
    console.error("fetchTradeFeedPostById:", error)
    return null
  }
  if (!data) return null
  return normalizeTradeFeedItem(data)
}

export async function fetchTradeFeedPostByTradeId(
  supabase: SupabaseClient,
  tradeId: string
): Promise<FeedItem | null> {
  const demo = findDemoFeedItemByTradeId(tradeId)
  if (demo) return demo
  if (isDemoModeActive()) return null

  const { data, error } = await supabase
    .from("posts")
    .select(FEED_POSTS_SELECT)
    .eq("trade_id", tradeId)
    .maybeSingle()
    .overrideTypes<Record<string, unknown> | null, { merge: false }>()

  if (error) {
    console.error("fetchTradeFeedPostByTradeId:", error)
    return null
  }
  if (!data) return null
  return normalizeTradeFeedItem(data)
}

export async function fetchProfileFeedPostById(
  supabase: SupabaseClient,
  postId: string
): Promise<FeedItem | null> {
  const demo = findDemoFeedItem(postId, "profile")
  if (demo) return demo
  if (isDemoModeActive()) return null

  const { data, error } = await supabase
    .from("profile_posts")
    .select(FEED_PROFILE_POSTS_SELECT)
    .eq("id", postId)
    .maybeSingle()
    .overrideTypes<Record<string, unknown> | null, { merge: false }>()

  if (error) {
    console.error("fetchProfileFeedPostById:", error)
    return null
  }
  if (!data) return null
  return normalizeProfileFeedItem(data)
}

export async function topUpMergedFeedBuffer(
  supabase: SupabaseClient,
  options: {
    scope: FeedScope
    userId: string
    followingIds: string[]
    buffer: FeedItem[]
    tradePage: number
    profilePage: number
    achievementPage: number
    reelPage: number
    tradeExhausted: boolean
    profileExhausted: boolean
    achievementExhausted: boolean
    reelExhausted: boolean
    targetSize: number
    pageSize?: number
  }
): Promise<{
  buffer: FeedItem[]
  tradePage: number
  profilePage: number
  achievementPage: number
  reelPage: number
  tradeExhausted: boolean
  profileExhausted: boolean
  achievementExhausted: boolean
  reelExhausted: boolean
}> {
  if (isDemoUserId(options.userId)) {
    return topUpDemoMergedFeedBuffer(options)
  }

  const pageSize = options.pageSize ?? FEED_PAGE_SIZE
  let buffer = dedupeFeedItems(options.buffer)
  let tradePage = options.tradePage
  let profilePage = options.profilePage
  let achievementPage = options.achievementPage
  let reelPage = options.reelPage
  let tradeExhausted = options.tradeExhausted
  let profileExhausted = options.profileExhausted
  let achievementExhausted = options.achievementExhausted
  let reelExhausted = options.reelExhausted

  while (
    buffer.length < options.targetSize &&
    !(tradeExhausted && profileExhausted && achievementExhausted && reelExhausted)
  ) {
    const fetches: Promise<FeedBatchResult>[] = []

    if (!tradeExhausted) {
      fetches.push(
        fetchTradeFeedBatch(supabase, {
          scope: options.scope,
          userId: options.userId,
          followingIds: options.followingIds,
          page: tradePage,
          pageSize,
        })
      )
    }

    if (!profileExhausted) {
      fetches.push(
        fetchProfileFeedBatch(supabase, {
          scope: options.scope,
          userId: options.userId,
          followingIds: options.followingIds,
          page: profilePage,
          pageSize,
        })
      )
    }

    if (!achievementExhausted) {
      fetches.push(
        fetchAchievementFeedBatch(supabase, {
          scope: options.scope,
          userId: options.userId,
          followingIds: options.followingIds,
          page: achievementPage,
          pageSize,
        })
      )
    }

    if (!reelExhausted) {
      fetches.push(
        fetchReelFeedBatch(supabase, {
          scope: options.scope,
          userId: options.userId,
          followingIds: options.followingIds,
          page: reelPage,
          pageSize,
        })
      )
    }

    if (fetches.length === 0) break

    const results = await Promise.all(fetches)
    let resultIndex = 0

    if (!tradeExhausted) {
      const tradeResult = results[resultIndex++]
      tradePage += 1
      if (tradeResult.items.length < pageSize) tradeExhausted = true
      buffer = dedupeFeedItems([...buffer, ...tradeResult.items])
    }

    if (!profileExhausted) {
      const profileResult = results[resultIndex++]
      profilePage += 1
      if (profileResult.items.length < pageSize) profileExhausted = true
      buffer = dedupeFeedItems([...buffer, ...profileResult.items])
    }

    if (!achievementExhausted) {
      const achievementResult = results[resultIndex++]
      achievementPage += 1
      if (achievementResult.items.length < pageSize) achievementExhausted = true
      buffer = dedupeFeedItems([...buffer, ...achievementResult.items])
    }

    if (!reelExhausted) {
      const reelResult = results[resultIndex]
      reelPage += 1
      if (reelResult.items.length < pageSize) reelExhausted = true
      buffer = dedupeFeedItems([...buffer, ...reelResult.items])
    }

    buffer = sortFeedItemsDesc(buffer)
  }

  buffer = await hydrateTradeFeedItemsWithReels(supabase, options.userId, buffer)

  return {
    buffer,
    tradePage,
    profilePage,
    achievementPage,
    reelPage,
    tradeExhausted,
    profileExhausted,
    achievementExhausted,
    reelExhausted,
  }
}
