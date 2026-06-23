import type { SupabaseClient } from "@supabase/supabase-js"
import {
  FEED_POSTS_SELECT,
  type FeedContentFilter,
  type FeedItem,
  type FeedScope,
  dedupeFeedItems,
  normalizeProfileFeedItem,
  normalizeTradeFeedItem,
  sortFeedItemsDesc,
} from "@/app/components/feed/feedPostHelpers"

export const FEED_PAGE_SIZE = 8

export const FEED_PROFILE_POSTS_SELECT =
  "id, user_id, content, image_url, created_at, room_id, room_name, room_logo, room_description, profiles(username, avatar_url)"

export async function fetchFollowingIds(
  supabase: SupabaseClient,
  userId: string
): Promise<string[]> {
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

  const { data, error } = await scoped
  if (error) throw error

  return {
    items: (data ?? []).map((row) => normalizeTradeFeedItem(row as Record<string, unknown>)),
  }
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

  const { data, error } = await scoped
  if (error) throw error

  return {
    items: (data ?? []).map((row) =>
      normalizeProfileFeedItem(row as Record<string, unknown>)
    ),
  }
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
    tradeExhausted: boolean
    profileExhausted: boolean
    targetSize: number
    pageSize?: number
  }
): Promise<{
  buffer: FeedItem[]
  tradePage: number
  profilePage: number
  tradeExhausted: boolean
  profileExhausted: boolean
}> {
  const pageSize = options.pageSize ?? FEED_PAGE_SIZE
  let buffer = dedupeFeedItems(options.buffer)
  let tradePage = options.tradePage
  let profilePage = options.profilePage
  let tradeExhausted = options.tradeExhausted
  let profileExhausted = options.profileExhausted

  while (
    buffer.length < options.targetSize &&
    !(tradeExhausted && profileExhausted)
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
      const profileResult = results[resultIndex]
      profilePage += 1
      if (profileResult.items.length < pageSize) profileExhausted = true
      buffer = dedupeFeedItems([...buffer, ...profileResult.items])
    }

    buffer = sortFeedItemsDesc(buffer)
  }

  return { buffer, tradePage, profilePage, tradeExhausted, profileExhausted }
}
