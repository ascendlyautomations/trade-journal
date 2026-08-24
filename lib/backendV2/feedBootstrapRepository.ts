/**
 * Feed bootstrap repositories (REST + RPC).
 * Flag OFF → production unchanged. Flag ON → one RPC hydrates Feed page 0+.
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import type { FeedItem, FeedContentFilter, FeedScope } from "@/app/components/feed/feedPostHelpers"
import {
  normalizeAchievementFeedItem,
  normalizeProfileFeedItem,
  normalizeReelFeedItem,
  normalizeTradeFeedItem,
} from "@/app/components/feed/feedPostHelpers"
import {
  ACTIVE_STORIES_SELECT,
  filterActiveStories,
  type ActiveStoryRow,
} from "@/lib/activeStories"
import {
  FEED_PAGE_SIZE,
  fetchAchievementFeedBatch,
  fetchFollowingIds,
  fetchProfileFeedBatch,
  fetchReelFeedBatch,
  fetchTradeFeedBatch,
  topUpMergedFeedBuffer,
} from "@/lib/feedContent"
import { fetchFeedEngagementMaps } from "@/lib/feedEngagementCounts"
import type { FeedBootstrapProviding } from "./adapters.ts"
import {
  decodeFeedBootstrapV1,
  type FeedBootstrapV1,
  type FeedContentFilterV1,
  type FeedItemKindV1,
  type FeedItemV1,
} from "./contracts.ts"
import {
  compareFeedBootstraps,
  logFeedBootstrapMismatches,
} from "./feedBootstrapCompare.ts"
import {
  feedBootstrapCacheKey,
  invalidateFeedBootstrap,
  readFeedBootstrapCache,
  writeFeedBootstrapCache,
} from "./feedBootstrapCache.ts"
import {
  beginFeedBootstrapFlight,
  getFeedBootstrapFlight,
} from "./feedBootstrapSingleFlight.ts"
import { isBackendV2Enabled } from "./flags.ts"
import {
  BackendV2RpcClient,
  createSupabaseBackendV2Transport,
} from "./rpcClient.ts"
import { getSessionFollowingIds } from "./sessionBootstrapCache.ts"
import {
  measureAsync,
  recordBackendV2Telemetry,
  utf8ByteLength,
} from "./telemetry.ts"
import { BackendV2RpcNames } from "./versioning.ts"

export type FeedBootstrapInput = {
  scope: FeedScope
  contentFilter?: FeedContentFilterV1
  cursor?: string | null
  limit?: number
}

function mapKindToFeedKind(kind: FeedItemKindV1): FeedItem["feedKind"] {
  switch (kind) {
    case "post":
    case "trade_card":
      return "trade"
    case "profile_post":
      return "profile"
    case "achievement_post":
      return "achievement"
    case "reel":
      return "reel"
    default:
      return "trade"
  }
}

/** Map Backend V2 feed item → web FeedItem for existing cards. */
export function feedItemV1ToFeedItem(item: FeedItemV1): FeedItem {
  const payload = (item.payload ?? {}) as Record<string, unknown>
  const feedKind = mapKindToFeedKind(item.kind)
  const base = {
    ...payload,
    id: item.id,
    user_id: item.author_id,
    created_at: item.created_at,
    feedKind,
  } as Record<string, unknown>

  if (feedKind === "trade") return normalizeTradeFeedItem(base)
  if (feedKind === "profile") return normalizeProfileFeedItem(base)
  if (feedKind === "achievement") return normalizeAchievementFeedItem(base)
  return normalizeReelFeedItem(base)
}

export function feedBootstrapToFeedItems(
  bootstrap: FeedBootstrapV1
): FeedItem[] {
  return bootstrap.data.items.map(feedItemV1ToFeedItem)
}

function engagementMapsFromBootstrap(bootstrap: FeedBootstrapV1): {
  likesMap: Record<string, { count: number; liked: boolean }>
  commentCountsMap: Record<string, number>
} {
  const likesMap: Record<string, { count: number; liked: boolean }> = {}
  const commentCountsMap: Record<string, number> = {}
  for (const [id, snap] of Object.entries(bootstrap.data.engagement)) {
    likesMap[id] = {
      count: Number(snap.like_count) || 0,
      liked: snap.liked_by_viewer === true,
    }
    commentCountsMap[id] = Number(snap.comment_count) || 0
  }
  return { likesMap, commentCountsMap }
}

export function feedBootstrapEngagementMaps(bootstrap: FeedBootstrapV1) {
  return engagementMapsFromBootstrap(bootstrap)
}

function webContentToFilter(
  contentType: FeedContentFilter
): FeedContentFilterV1 {
  return contentType as FeedContentFilterV1
}

export { webContentToFilter }

async function resolveFollowingIds(
  client: SupabaseClient,
  userId: string
): Promise<string[]> {
  const fromSession = getSessionFollowingIds(userId)
  if (fromSession) return fromSession
  return fetchFollowingIds(client, userId)
}

function toFeedItemV1(
  item: FeedItem,
  kind: FeedItemKindV1
): FeedItemV1 {
  const { feedKind: _fk, ...payload } = item
  return {
    kind,
    id: String(item.id),
    created_at: String(item.created_at),
    author_id: String(item.user_id),
    payload: payload as Record<string, unknown>,
  }
}

function kindForFeedItem(item: FeedItem): FeedItemKindV1 {
  switch (item.feedKind) {
    case "trade":
      return "post"
    case "profile":
      return "profile_post"
    case "achievement":
      return "achievement_post"
    case "reel":
      return "reel"
    default:
      return "post"
  }
}

export class FeedRestBootstrapRepository implements FeedBootstrapProviding {
  constructor(
    private readonly client: SupabaseClient,
    private readonly userId: string
  ) {}

  async loadFeedBootstrap(input: FeedBootstrapInput): Promise<FeedBootstrapV1> {
    const uid = this.userId
    const scope = input.scope
    const contentFilter = input.contentFilter ?? "all"
    const limit = Math.max(1, Math.min(input.limit ?? FEED_PAGE_SIZE, 40))
    const followingIds = await resolveFollowingIds(this.client, uid)

    const serverTime = new Date().toISOString()
    const empty: FeedBootstrapV1 = {
      meta: {
        contract_version: "v1",
        server_time: serverTime,
        viewer_id: uid,
      },
      data: {
        scope,
        content_filter: contentFilter,
        items: [],
        authors: {},
        engagement: {},
        stories: [],
        story_authors: {},
        next_cursor: null,
        page_meta: { limit, returned: 0, has_more: false },
        following_ids_echo: followingIds,
      },
    }

    if (scope === "following" && followingIds.length === 0) {
      return empty
    }

    // Cursor pagination approximates REST offset page 0 only for dual-run;
    // REST path for load-more still uses page indexes in the UI when flag OFF.
    let list: FeedItem[] = []
    let hasMore = false

    if (contentFilter === "all") {
      const topped = await topUpMergedFeedBuffer(this.client, {
        scope,
        userId: uid,
        followingIds,
        buffer: [],
        tradePage: 0,
        profilePage: 0,
        achievementPage: 0,
        reelPage: 0,
        tradeExhausted: false,
        profileExhausted: false,
        achievementExhausted: false,
        reelExhausted: false,
        targetSize: limit + 1,
        pageSize: limit,
      })
      const buffer = topped.buffer
      hasMore = buffer.length > limit
      list = buffer.slice(0, limit)
    } else if (contentFilter === "trades") {
      const result = await fetchTradeFeedBatch(this.client, {
        scope,
        userId: uid,
        followingIds,
        page: 0,
        pageSize: limit + 1,
      })
      hasMore = result.items.length > limit
      list = result.items.slice(0, limit)
    } else if (contentFilter === "posts") {
      const result = await fetchProfileFeedBatch(this.client, {
        scope,
        userId: uid,
        followingIds,
        page: 0,
        pageSize: limit + 1,
      })
      hasMore = result.items.length > limit
      list = result.items.slice(0, limit)
    } else if (contentFilter === "achievements") {
      const result = await fetchAchievementFeedBatch(this.client, {
        scope,
        userId: uid,
        followingIds,
        page: 0,
        pageSize: limit + 1,
      })
      hasMore = result.items.length > limit
      list = result.items.slice(0, limit)
    } else {
      const result = await fetchReelFeedBatch(this.client, {
        scope,
        userId: uid,
        followingIds,
        page: 0,
        pageSize: limit + 1,
      })
      hasMore = result.items.length > limit
      list = result.items.slice(0, limit)
    }

    const tradeIds = list.filter((i) => i.feedKind === "trade").map((i) => String(i.id))
    const profileIds = list
      .filter((i) => i.feedKind === "profile")
      .map((i) => String(i.id))
    const achievementIds = list
      .filter((i) => i.feedKind === "achievement")
      .map((i) => String(i.id))
    const reelIds = list.filter((i) => i.feedKind === "reel").map((i) => String(i.id))
    const seedIds = list.map((i) => String(i.id))

    const eng = await fetchFeedEngagementMaps(this.client, {
      tradeIds,
      profileIds,
      achievementIds,
      reelIds,
      seedIds,
      currentUserId: uid,
    })

    const engagement: FeedBootstrapV1["data"]["engagement"] = {}
    for (const id of seedIds) {
      engagement[id] = {
        like_count: eng.likesMap[id]?.count ?? 0,
        comment_count: eng.commentCountsMap[id] ?? 0,
        liked_by_viewer: eng.likesMap[id]?.liked === true,
      }
    }

    const authors: FeedBootstrapV1["data"]["authors"] = {}
    for (const item of list) {
      const profiles = item.profiles as
        | { username?: string | null; avatar_url?: string | null }
        | { username?: string | null; avatar_url?: string | null }[]
        | null
        | undefined
      const row = Array.isArray(profiles) ? profiles[0] : profiles
      const id = String(item.user_id)
      if (!authors[id]) {
        authors[id] = {
          id,
          username: row?.username != null ? String(row.username) : null,
          display_name: row?.username != null ? String(row.username) : null,
          avatar_url: row?.avatar_url != null ? String(row.avatar_url) : null,
        }
      }
    }

    let stories: FeedBootstrapV1["data"]["stories"] = []
    let story_authors: FeedBootstrapV1["data"]["story_authors"] = {}
    if (scope === "following") {
      const storyUserIds = [...new Set([...followingIds, uid])]
      const { data: storyRows } = await this.client
        .from("stories")
        .select(ACTIVE_STORIES_SELECT)
        .in("user_id", storyUserIds)
        .order("created_at", { ascending: false })
      const active = filterActiveStories((storyRows ?? []) as ActiveStoryRow[])
      stories = active.map((s) => ({
        id: String(s.id),
        user_id: String(s.user_id),
        image_url: String(s.image_url),
        created_at: String(s.created_at),
      }))
      const storyAuthorIds = [...new Set(stories.map((s) => s.user_id))]
      if (storyAuthorIds.length) {
        const { data: profiles } = await this.client
          .from("profiles")
          .select("id, username, avatar_url")
          .in("id", storyAuthorIds)
        for (const p of profiles ?? []) {
          const id = String((p as { id: string }).id)
          story_authors[id] = {
            id,
            username:
              (p as { username?: string | null }).username != null
                ? String((p as { username?: string | null }).username)
                : null,
            display_name:
              (p as { username?: string | null }).username != null
                ? String((p as { username?: string | null }).username)
                : null,
            avatar_url:
              (p as { avatar_url?: string | null }).avatar_url != null
                ? String((p as { avatar_url?: string | null }).avatar_url)
                : null,
          }
        }
      }
    }

    const last = list[list.length - 1]
    const next_cursor =
      hasMore && last?.created_at ? String(last.created_at) : null

    return {
      meta: {
        contract_version: "v1",
        server_time: serverTime,
        viewer_id: uid,
      },
      data: {
        scope,
        content_filter: contentFilter,
        items: list.map((item) => toFeedItemV1(item, kindForFeedItem(item))),
        authors,
        engagement,
        stories,
        story_authors,
        next_cursor,
        page_meta: {
          limit,
          returned: list.length,
          has_more: hasMore,
        },
        following_ids_echo: followingIds,
      },
    }
  }
}

export class FeedRpcBootstrapRepository implements FeedBootstrapProviding {
  private readonly client: BackendV2RpcClient

  constructor(supabase: SupabaseClient) {
    this.client = new BackendV2RpcClient({
      transport: createSupabaseBackendV2Transport(supabase),
    })
  }

  async loadFeedBootstrap(input: FeedBootstrapInput): Promise<FeedBootstrapV1> {
    const args: Record<string, unknown> = {
      p_scope: input.scope,
      p_content_filter: input.contentFilter ?? "all",
      p_limit: input.limit ?? FEED_PAGE_SIZE,
    }
    if (input.cursor) args.p_cursor = input.cursor
    return this.client.callKnown(
      BackendV2RpcNames.feed,
      decodeFeedBootstrapV1,
      {
        args,
        flagName: "backendV2.feed",
        cacheMiss: true,
      }
    )
  }
}

export type FeedBootstrapLoadResult = {
  bootstrap: FeedBootstrapV1
  source: "rpc" | "rest" | "cache"
  dualRunMismatches: number
  rpcRequestCount: number
  durationMs: number
  payloadBytes: number
  cacheHit: boolean
}

export async function loadFeedBootstrapForUser(
  client: SupabaseClient,
  userId: string,
  options: FeedBootstrapInput & {
    force?: boolean
    caller?: string
  }
): Promise<FeedBootstrapLoadResult> {
  const uid = userId.trim()
  if (!uid) throw new Error("loadFeedBootstrapForUser requires userId")
  if (!isBackendV2Enabled("feed")) {
    throw new Error("loadFeedBootstrapForUser requires backendV2.feed flag ON")
  }

  const scope = options.scope
  const contentFilter = options.contentFilter ?? "all"
  const cursor = options.cursor?.trim() || null
  const limit = options.limit ?? FEED_PAGE_SIZE
  const key = feedBootstrapCacheKey({
    userId: uid,
    scope,
    contentFilter,
    cursor,
  })

  if (options.force) {
    invalidateFeedBootstrap(uid)
  }

  if (!options.force && !cursor) {
    const cached = readFeedBootstrapCache(key)
    if (cached) {
      return {
        bootstrap: cached,
        source: "cache",
        dualRunMismatches: 0,
        rpcRequestCount: 0,
        durationMs: 0,
        payloadBytes: 0,
        cacheHit: true,
      }
    }
    const existing = getFeedBootstrapFlight<FeedBootstrapLoadResult>(key)
    if (existing) return existing
  }

  return beginFeedBootstrapFlight(key, uid, async () => {
    if (!options.force && !cursor) {
      const cached = readFeedBootstrapCache(key)
      if (cached) {
        return {
          bootstrap: cached,
          source: "cache",
          dualRunMismatches: 0,
          rpcRequestCount: 0,
          durationMs: 0,
          payloadBytes: 0,
          cacheHit: true,
        }
      }
    }

    const rpcRepo = new FeedRpcBootstrapRepository(client)
    const restRepo = new FeedRestBootstrapRepository(client, uid)
    const input: FeedBootstrapInput = {
      scope,
      contentFilter,
      cursor,
      limit,
    }

    const { value: rpc, ms } = await measureAsync(() =>
      rpcRepo.loadFeedBootstrap(input)
    )

    let dualRunMismatches = 0
    const dualRun =
      process.env.NODE_ENV === "development" &&
      (process.env.NEXT_PUBLIC_BACKEND_V2_DUAL_RUN === "1" ||
        process.env.NEXT_PUBLIC_BACKEND_V2_DUAL_RUN === "true")
    if (dualRun && !cursor) {
      try {
        const rest = await restRepo.loadFeedBootstrap(input)
        const mismatches = compareFeedBootstraps(rest, rpc)
        dualRunMismatches = mismatches.length
        logFeedBootstrapMismatches(mismatches)
      } catch (err) {
        console.warn("[backendV2.feed] dual-run REST failed", err)
        dualRunMismatches = -1
      }
    }

    if (!cursor) {
      writeFeedBootstrapCache(key, uid, rpc, "rpc")
    }

    let payloadBytes = 0
    try {
      payloadBytes = utf8ByteLength(JSON.stringify(rpc))
    } catch {
      payloadBytes = 0
    }

    recordBackendV2Telemetry({
      rpcName: BackendV2RpcNames.feed,
      success: true,
      executionMs: ms,
      decodeMs: null,
      payloadBytes,
      cacheHit: false,
      cacheMiss: true,
      errorCode: null,
      flagName: "backendV2.feed",
    })

    return {
      bootstrap: rpc,
      source: "rpc",
      dualRunMismatches,
      rpcRequestCount: 1,
      durationMs: ms,
      payloadBytes,
      cacheHit: false,
    }
  })
}

export {
  clearFeedBootstrapCache,
  invalidateFeedBootstrap,
  readFeedBootstrapCache,
} from "./feedBootstrapCache.ts"
