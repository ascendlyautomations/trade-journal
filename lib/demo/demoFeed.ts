import type { FeedItem, FeedItemKind, FeedScope } from "@/app/components/feed/feedPostHelpers"
import {
  normalizeAchievementFeedItem,
  normalizeProfileFeedItem,
  normalizeReelFeedItem,
  normalizeTradeFeedItem,
  sortFeedItemsDesc,
} from "@/app/components/feed/feedPostHelpers"
import { FEED_PAGE_SIZE } from "@/lib/feedContent"
import type { ActiveStoryRow, StoryBarProfile } from "@/lib/activeStories"
import { DEMO_USER_ID } from "./constants"
import { DEMO_PROFILE, DEMO_TRADE_ROOMS } from "./fixtures"
import { demoAvatarUrl, demoReelThumbnailUrl } from "./demoAvatars"
import {
  demoPostImageUrl,
  demoStaticImageUrl,
  demoStoryImageUrl,
  demoTradeScreenshotUrl,
} from "./demoAssets"

export const DEMO_USER_ALEX = "demo-user-alex"
export const DEMO_USER_JORDAN = "demo-user-jordan"
export const DEMO_USER_SARAH = "demo-user-sarah"
export const DEMO_USER_MIKE = "demo-user-mike"
export const DEMO_USER_ELI = "demo-user-eli"

export const DEMO_FOLLOWING_IDS = [
  DEMO_USER_ALEX,
  DEMO_USER_JORDAN,
  DEMO_USER_SARAH,
  DEMO_USER_MIKE,
]

const DEMO_FEED_PROFILES: Record<
  string,
  { username: string; avatar_url: string | null }
> = {
  [DEMO_USER_ID]: { username: DEMO_PROFILE.username, avatar_url: null },
  [DEMO_USER_ALEX]: { username: "alex_futures", avatar_url: null },
  [DEMO_USER_JORDAN]: { username: "jordan_scalps", avatar_url: null },
  [DEMO_USER_SARAH]: { username: "sarah_indices", avatar_url: null },
  [DEMO_USER_MIKE]: { username: "mike_swings", avatar_url: null },
  [DEMO_USER_ELI]: { username: "eli_prop", avatar_url: null },
}

function isoTradeTime(daysAgo: number, hour: number): string {
  const d = new Date()
  d.setHours(hour, 15, 0, 0)
  d.setDate(d.getDate() - daysAgo)
  return d.toISOString()
}

function profileFor(userId: string) {
  const base =
    DEMO_FEED_PROFILES[userId] ?? {
      username: "trader",
      avatar_url: null,
    }
  return {
    ...base,
    avatar_url: demoAvatarUrl(userId),
  }
}

const RAW_FEED_ROWS: Record<string, unknown>[] = [
  {
    id: "demo-post-1",
    user_id: DEMO_USER_ID,
    trade_id: "dt-24",
    created_at: isoTradeTime(0, 10),
    pnl: 1050,
    rr: 2.7,
    image_url: demoTradeScreenshotUrl("dt-24", { direction: "Long", pnl: 1050 }),
    profiles: profileFor(DEMO_USER_ID),
    trades: {
      user_id: DEMO_USER_ID,
      created_at: isoTradeTime(0, 10),
      ticker: "NQ",
      direction: "Long",
      account_type: "prop",
      points: 52,
      entry_time: isoTradeTime(0, 10),
      exit_time: isoTradeTime(0, 10),
      entry_price: 19010,
      exit_price: 19062,
      trade_date: isoTradeTime(0, 10).slice(0, 10),
      duration_seconds: 1080,
      duration_text: "18m",
      public_description:
        "Clean opening drive long — waited for liquidity sweep, entered on 1m BOS. Took partials at VWAP extension.",
    },
  },
  {
    id: "demo-post-2",
    user_id: DEMO_USER_ALEX,
    trade_id: "demo-trade-alex-1",
    created_at: isoTradeTime(1, 11),
    pnl: 720,
    rr: 2.1,
    image_url: demoTradeScreenshotUrl("demo-trade-alex-1", { direction: "Short", pnl: 720 }),
    profiles: profileFor(DEMO_USER_ALEX),
    trades: {
      user_id: DEMO_USER_ALEX,
      created_at: isoTradeTime(1, 11),
      ticker: "ES",
      direction: "Short",
      account_type: "prop",
      points: 12,
      entry_time: isoTradeTime(1, 11),
      exit_time: isoTradeTime(1, 11),
      entry_price: 5458,
      exit_price: 5446,
      trade_date: isoTradeTime(1, 11).slice(0, 10),
      duration_seconds: 900,
      duration_text: "15m",
      public_description:
        "Reversal off overnight high. Shared the full breakdown in Trade Rooms earlier.",
    },
  },
  {
    id: "demo-post-3",
    user_id: DEMO_USER_JORDAN,
    trade_id: "demo-trade-jordan-1",
    created_at: isoTradeTime(2, 14),
    pnl: -280,
    rr: 0.6,
    image_url: demoTradeScreenshotUrl("demo-trade-jordan-1", { direction: "Long", pnl: -280 }),
    profiles: profileFor(DEMO_USER_JORDAN),
    trades: {
      user_id: DEMO_USER_JORDAN,
      created_at: isoTradeTime(2, 14),
      ticker: "NQ",
      direction: "Long",
      account_type: "personal",
      points: -14,
      entry_time: isoTradeTime(2, 14),
      exit_time: isoTradeTime(2, 14),
      entry_price: 18980,
      exit_price: 18966,
      trade_date: isoTradeTime(2, 14).slice(0, 10),
      duration_seconds: 600,
      duration_text: "10m",
      public_description:
        "Took a loss today — rushed entry before confirmation. Journal notes saved for review.",
    },
  },
  {
    id: "demo-post-4",
    user_id: DEMO_USER_SARAH,
    trade_id: "demo-trade-sarah-1",
    created_at: isoTradeTime(3, 9),
    pnl: 890,
    rr: 2.4,
    image_url: demoTradeScreenshotUrl("demo-trade-sarah-1", { direction: "Long", pnl: 890 }),
    profiles: profileFor(DEMO_USER_SARAH),
    trades: {
      user_id: DEMO_USER_SARAH,
      created_at: isoTradeTime(3, 9),
      ticker: "ES",
      direction: "Long",
      account_type: "prop",
      points: 18,
      entry_time: isoTradeTime(3, 9),
      exit_time: isoTradeTime(3, 9),
      entry_price: 5432,
      exit_price: 5450,
      trade_date: isoTradeTime(3, 9).slice(0, 10),
      duration_seconds: 1200,
      duration_text: "20m",
      public_description: "London open continuation — held through first pullback with plan intact.",
    },
  },
  {
    id: "demo-post-5",
    user_id: DEMO_USER_MIKE,
    trade_id: "demo-trade-mike-1",
    created_at: isoTradeTime(4, 13),
    pnl: 540,
    rr: 1.9,
    image_url: demoTradeScreenshotUrl("demo-trade-mike-1", { direction: "Short", pnl: 540 }),
    profiles: profileFor(DEMO_USER_MIKE),
    trades: {
      user_id: DEMO_USER_MIKE,
      created_at: isoTradeTime(4, 13),
      ticker: "NQ",
      direction: "Short",
      account_type: "prop",
      points: 27,
      entry_time: isoTradeTime(4, 13),
      exit_time: isoTradeTime(4, 13),
      entry_price: 19120,
      exit_price: 19093,
      trade_date: isoTradeTime(4, 13).slice(0, 10),
      duration_seconds: 720,
      duration_text: "12m",
      public_description: "Afternoon fade into close — textbook mean reversion setup.",
    },
  },
  {
    id: "demo-post-6",
    user_id: DEMO_USER_ELI,
    trade_id: "demo-trade-eli-1",
    created_at: isoTradeTime(5, 10),
    pnl: 1180,
    rr: 3.0,
    image_url: demoTradeScreenshotUrl("demo-trade-eli-1", { direction: "Long", pnl: 1180 }),
    profiles: profileFor(DEMO_USER_ELI),
    trades: {
      user_id: DEMO_USER_ELI,
      created_at: isoTradeTime(5, 10),
      ticker: "NQ",
      direction: "Long",
      account_type: "prop",
      points: 59,
      entry_time: isoTradeTime(5, 10),
      exit_time: isoTradeTime(5, 10),
      entry_price: 18840,
      exit_price: 18899,
      trade_date: isoTradeTime(5, 10).slice(0, 10),
      duration_seconds: 960,
      duration_text: "16m",
      public_description: "Passed my eval last week — sharing the trade that put me over profit target.",
    },
  },
  {
    id: "demo-profile-1",
    user_id: DEMO_USER_ALEX,
    content:
      "Who else is watching NQ into CPI tomorrow? Planning to size down and wait for the first 15m structure.",
    image_url: demoPostImageUrl("demo-profile-1"),
    created_at: isoTradeTime(0, 8),
    room_id: null,
    profiles: profileFor(DEMO_USER_ALEX),
  },
  {
    id: "demo-profile-2",
    user_id: DEMO_USER_SARAH,
    content:
      "Just hit 5 winning days on my eval — consistency rule was the hardest part. Tracking everything in Prop Firm Mode helped.",
    image_url: demoPostImageUrl("demo-profile-2"),
    created_at: isoTradeTime(1, 16),
    room_id: null,
    profiles: profileFor(DEMO_USER_SARAH),
  },
  {
    id: "demo-profile-3",
    user_id: DEMO_USER_JORDAN,
    content: "Join us for live commentary during the US open.",
    image_url: null,
    created_at: isoTradeTime(2, 7),
    room_id: DEMO_TRADE_ROOMS[0].id,
    room_name: DEMO_TRADE_ROOMS[0].name,
    room_logo: null,
    room_description: DEMO_TRADE_ROOMS[0].preview,
    profiles: profileFor(DEMO_USER_JORDAN),
  },
  {
    id: "demo-achievement-1",
    user_id: DEMO_USER_ALEX,
    achievement_id: "demo-ach-1",
    created_at: isoTradeTime(2, 12),
    metadata: null,
    achievements: {
      id: "demo-ach-1",
      title: "Prop Firm Passed",
      description: "Apex 150K evaluation cleared",
      achievement_type: "milestone",
      badge_key: "prop_pass",
      tier: "gold",
      value_text: "150K",
      value_numeric: 150000,
      currency: "USD",
      achieved_at: isoTradeTime(14, 10),
      is_public: true,
      is_featured: true,
      category: "prop_firm",
      firm: "Apex",
      metadata: null,
      image_url: demoStaticImageUrl("demo-ach-feed-1"),
    },
    profiles: profileFor(DEMO_USER_ALEX),
  },
  {
    id: "demo-achievement-2",
    user_id: DEMO_USER_MIKE,
    achievement_id: "demo-ach-2",
    created_at: isoTradeTime(4, 9),
    metadata: null,
    achievements: {
      id: "demo-ach-2",
      title: "100 Trades Logged",
      description: "Consistency builds edge",
      achievement_type: "milestone",
      badge_key: "trades_100",
      tier: "silver",
      value_text: "100",
      value_numeric: 100,
      currency: null,
      image_url: demoStaticImageUrl("demo-ach-feed-2"),
      achieved_at: isoTradeTime(20, 11),
      is_public: true,
      is_featured: false,
      category: "journal",
      firm: null,
      metadata: null,
    },
    profiles: profileFor(DEMO_USER_MIKE),
  },
  {
    id: "demo-reel-1",
    user_id: DEMO_USER_ID,
    caption: null,
    video_url:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    thumbnail_url: demoReelThumbnailUrl("demo-reel-1"),
    cover_url: demoReelThumbnailUrl("demo-reel-1"),
    duration_seconds: 42,
    view_count: 2400,
    visibility: "public",
    trade_id: "dt-24",
    kind: null,
    created_at: isoTradeTime(1, 15),
    trades: {
      id: "dt-24",
      public_description: "NQ opening drive — liquidity sweep and BOS entry.",
      is_public: true,
      ticker: "NQ",
      direction: "Long",
      pnl: 1050,
      rr: 2.7,
    },
    profiles: profileFor(DEMO_USER_ID),
  },
  {
    id: "demo-reel-2",
    user_id: DEMO_USER_ALEX,
    caption: "How I Passed My Eval — rule tracking workflow",
    video_url:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
    thumbnail_url: demoReelThumbnailUrl("demo-reel-2"),
    cover_url: demoReelThumbnailUrl("demo-reel-2"),
    duration_seconds: 75,
    view_count: 5100,
    visibility: "public",
    created_at: isoTradeTime(3, 10),
    profiles: profileFor(DEMO_USER_ALEX),
  },
  {
    id: "demo-reel-3",
    user_id: DEMO_USER_ELI,
    caption: "3 Mistakes From Last Week — journal review",
    video_url:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
    thumbnail_url: demoReelThumbnailUrl("demo-reel-3"),
    cover_url: demoReelThumbnailUrl("demo-reel-3"),
    duration_seconds: 58,
    view_count: 1800,
    visibility: "public",
    created_at: isoTradeTime(6, 11),
    profiles: profileFor(DEMO_USER_ELI),
  },
]

function buildDemoFeedItems(): FeedItem[] {
  const items: FeedItem[] = []
  for (const row of RAW_FEED_ROWS) {
    if ("trade_id" in row) {
      items.push(normalizeTradeFeedItem(row))
    } else if ("achievement_id" in row) {
      items.push(normalizeAchievementFeedItem(row))
    } else if ("video_url" in row) {
      items.push(normalizeReelFeedItem(row))
    } else {
      items.push(normalizeProfileFeedItem(row))
    }
  }
  return sortFeedItemsDesc(items)
}

export const DEMO_FEED_ITEMS = buildDemoFeedItems()

type LikeMeta = { count: number; liked: boolean }

export const DEMO_FEED_LIKES: Record<string, LikeMeta> = {
  "demo-post-1": { count: 24, liked: false },
  "demo-post-2": { count: 18, liked: true },
  "demo-post-3": { count: 6, liked: false },
  "demo-post-4": { count: 31, liked: false },
  "demo-post-5": { count: 14, liked: false },
  "demo-post-6": { count: 67, liked: true },
  "demo-profile-1": { count: 12, liked: false },
  "demo-profile-2": { count: 45, liked: true },
  "demo-profile-3": { count: 8, liked: false },
  "demo-achievement-1": { count: 52, liked: false },
  "demo-achievement-2": { count: 38, liked: false },
  "demo-reel-1": { count: 89, liked: false },
  "demo-reel-2": { count: 156, liked: true },
  "demo-reel-3": { count: 64, liked: false },
}

export const DEMO_FEED_COMMENTS: Record<string, any[]> = {
  "demo-post-1": [
    {
      id: "demo-comment-1",
      post_id: "demo-post-1",
      user_id: DEMO_USER_ALEX,
      content: "Clean execution — that BOS entry was textbook.",
      created_at: isoTradeTime(0, 11),
      profiles: profileFor(DEMO_USER_ALEX),
    },
    {
      id: "demo-comment-2",
      post_id: "demo-post-1",
      user_id: DEMO_USER_SARAH,
      content: "What timeframe for the sweep?",
      created_at: isoTradeTime(0, 12),
      profiles: profileFor(DEMO_USER_SARAH),
    },
  ],
  "demo-post-2": [
    {
      id: "demo-comment-3",
      post_id: "demo-post-2",
      user_id: DEMO_USER_ID,
      content: "Nice reversal — been waiting for that level all week.",
      created_at: isoTradeTime(1, 12),
      profiles: profileFor(DEMO_USER_ID),
    },
  ],
  "demo-profile-1": [
    {
      id: "demo-comment-4",
      profile_post_id: "demo-profile-1",
      user_id: DEMO_USER_JORDAN,
      content: "Sizing down for CPI too. Better to miss than force it.",
      created_at: isoTradeTime(0, 9),
      profiles: profileFor(DEMO_USER_JORDAN),
    },
  ],
  "demo-reel-1": [
    {
      id: "demo-comment-5",
      reel_id: "demo-reel-1",
      user_id: DEMO_USER_MIKE,
      content: "This breakdown helped my morning routine — thanks!",
      created_at: isoTradeTime(1, 16),
      profiles: profileFor(DEMO_USER_MIKE),
    },
  ],
  "demo-reel-2": [
    {
      id: "demo-comment-6",
      reel_id: "demo-reel-2",
      user_id: DEMO_USER_SARAH,
      content: "This eval workflow is exactly what I needed — saving this.",
      created_at: isoTradeTime(3, 11),
      profiles: profileFor(DEMO_USER_SARAH),
    },
  ],
  "demo-reel-3": [
    {
      id: "demo-comment-7",
      reel_id: "demo-reel-3",
      user_id: DEMO_USER_JORDAN,
      content: "Honest review — appreciate the transparency on the losses.",
      created_at: isoTradeTime(6, 12),
      profiles: profileFor(DEMO_USER_JORDAN),
    },
  ],
}

export const DEMO_STORIES: ActiveStoryRow[] = [
  {
    id: "demo-story-1",
    user_id: DEMO_USER_ALEX,
    image_url: demoStoryImageUrl("demo-story-1"),
    created_at: isoTradeTime(0, 7),
  },
  {
    id: "demo-story-2",
    user_id: DEMO_USER_ALEX,
    image_url: demoStoryImageUrl("demo-story-2"),
    created_at: isoTradeTime(0, 8),
  },
  {
    id: "demo-story-3",
    user_id: DEMO_USER_JORDAN,
    image_url: demoStoryImageUrl("demo-story-3"),
    created_at: isoTradeTime(0, 9),
  },
  {
    id: "demo-story-4",
    user_id: DEMO_USER_SARAH,
    image_url: demoStoryImageUrl("demo-story-4"),
    created_at: isoTradeTime(0, 6),
  },
]

function applyScope(
  items: FeedItem[],
  scope: FeedScope,
  userId: string,
  followingIds: string[]
): FeedItem[] {
  const followingSet = new Set(followingIds.map(String))
  return items.filter((item) => {
    const authorId = String(item.user_id)
    if (authorId === userId) return false
    if (scope === "following") {
      return followingSet.has(authorId)
    }
    return !followingSet.has(authorId)
  })
}

function filterByKind(items: FeedItem[], kind: FeedItemKind): FeedItem[] {
  return items.filter((item) => item.feedKind === kind)
}

export function getDemoFollowingIds(_userId: string): string[] {
  return [...DEMO_FOLLOWING_IDS]
}

export function fetchDemoFeedBatch(options: {
  scope: FeedScope
  userId: string
  followingIds: string[]
  kind?: FeedItemKind | "all"
  page: number
  pageSize?: number
}): { items: FeedItem[]; emptyFollowing?: boolean } {
  const pageSize = options.pageSize ?? FEED_PAGE_SIZE

  if (options.scope === "following" && options.followingIds.length === 0) {
    return { items: [], emptyFollowing: true }
  }

  let pool = applyScope(
    DEMO_FEED_ITEMS,
    options.scope,
    options.userId,
    options.followingIds
  )

  if (options.kind && options.kind !== "all") {
    pool = filterByKind(pool, options.kind)
  }

  const from = options.page * pageSize
  const items = pool.slice(from, from + pageSize)
  return { items }
}

export function topUpDemoMergedFeedBuffer(options: {
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
}) {
  const pageSize = options.pageSize ?? FEED_PAGE_SIZE
  let buffer = [...options.buffer]
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
    const batch: FeedItem[] = []

    if (!tradeExhausted) {
      const r = fetchDemoFeedBatch({
        scope: options.scope,
        userId: options.userId,
        followingIds: options.followingIds,
        kind: "trade",
        page: tradePage,
        pageSize,
      })
      tradePage += 1
      if (r.items.length < pageSize) tradeExhausted = true
      batch.push(...r.items)
    }
    if (!profileExhausted) {
      const r = fetchDemoFeedBatch({
        scope: options.scope,
        userId: options.userId,
        followingIds: options.followingIds,
        kind: "profile",
        page: profilePage,
        pageSize,
      })
      profilePage += 1
      if (r.items.length < pageSize) profileExhausted = true
      batch.push(...r.items)
    }
    if (!achievementExhausted) {
      const r = fetchDemoFeedBatch({
        scope: options.scope,
        userId: options.userId,
        followingIds: options.followingIds,
        kind: "achievement",
        page: achievementPage,
        pageSize,
      })
      achievementPage += 1
      if (r.items.length < pageSize) achievementExhausted = true
      batch.push(...r.items)
    }
    if (!reelExhausted) {
      const r = fetchDemoFeedBatch({
        scope: options.scope,
        userId: options.userId,
        followingIds: options.followingIds,
        kind: "reel",
        page: reelPage,
        pageSize,
      })
      reelPage += 1
      if (r.items.length < pageSize) reelExhausted = true
      batch.push(...r.items)
    }

    if (batch.length === 0) break

    const merged = sortFeedItemsDesc([...buffer, ...batch])
    const seen = new Set<string>()
    buffer = merged.filter((item) => {
      const key = `${item.feedKind}:${item.id}`
      if (seen.has(key)) return false
      seen.add(key)
      return true
    })
  }

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

export function findDemoFeedItem(
  id: string,
  kind?: FeedItemKind
): FeedItem | null {
  const hit = DEMO_FEED_ITEMS.find((item) => {
    if (String(item.id) !== id) return false
    if (kind && item.feedKind !== kind) return false
    return true
  })
  return hit ?? null
}

export function findDemoFeedItemByTradeId(tradeId: string): FeedItem | null {
  return (
    DEMO_FEED_ITEMS.find(
      (item) =>
        item.feedKind === "trade" &&
        String((item as Record<string, unknown>).trade_id) === tradeId
    ) ?? null
  )
}

export function loadDemoFeedEngagement(
  postList: any[],
  currentUser: { id: string } | null
) {
  const likesMap: Record<string, LikeMeta> = {}
  const commentsMap: Record<string, any[]> = {}

  for (const p of postList) {
    const key = String(p.id)
    const likes = DEMO_FEED_LIKES[key] ?? { count: 0, liked: false }
    likesMap[key] = {
      count: likes.count,
      liked: currentUser ? likes.liked : false,
    }
    commentsMap[key] = [...(DEMO_FEED_COMMENTS[key] ?? [])]
  }

  const enriched = postList.map((p) => ({
    ...p,
    likesCount: likesMap[String(p.id)]?.count ?? 0,
  }))

  return { enriched, likesMap, commentsMap }
}

export function getDemoStoriesForUserIds(userIds: string[]): ActiveStoryRow[] {
  const idSet = new Set(userIds.map(String))
  return DEMO_STORIES.filter((s) => idSet.has(String(s.user_id)))
}

export function getDemoAchievementPostIdsByAchievementIds(
  achievementIds: string[]
): Record<string, string> {
  const wanted = new Set(
    achievementIds.map((id) => id.trim()).filter(Boolean)
  )
  if (wanted.size === 0) return {}

  const map: Record<string, string> = {}
  for (const item of DEMO_FEED_ITEMS) {
    if (item.feedKind !== "achievement") continue
    const achievementId = String(
      (item as Record<string, unknown>).achievement_id ?? ""
    ).trim()
    if (!achievementId || !wanted.has(achievementId)) continue
    map[achievementId] = String(item.id)
  }
  return map
}

export function getDemoStoryBarProfiles(userIds: string[]): StoryBarProfile[] {
  return userIds
    .map((id) => ({
      id,
      username: profileFor(id).username,
      avatar_url: profileFor(id).avatar_url,
    }))
    .filter((p) => DEMO_STORIES.some((s) => String(s.user_id) === p.id))
}
