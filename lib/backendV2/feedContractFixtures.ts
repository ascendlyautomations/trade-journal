/**
 * Phase B2: Feed bootstrap contract fixtures — all scope/filter scenarios.
 */

import type { FeedBootstrapV1, FeedItemV1 } from "./contracts.ts"

const VIEWER_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
const AUTHOR_A = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
const AUTHOR_B = "cccccccc-cccc-cccc-cccc-cccccccccccc"
const TS = "2026-08-20T12:00:00.000Z"
const TS_EQUAL = "2026-08-20T11:00:00.000Z"

const meta = {
  contract_version: "v1" as const,
  server_time: TS,
  viewer_id: VIEWER_ID,
}

const authorCard = (id: string, username: string, avatar: string | null) => ({
  id,
  username,
  display_name: username,
  avatar_url: avatar,
})

function baseFeed(
  overrides: Partial<FeedBootstrapV1["data"]> & {
    scope: FeedBootstrapV1["data"]["scope"]
    content_filter: FeedBootstrapV1["data"]["content_filter"]
  }
): FeedBootstrapV1 {
  return {
    meta,
    data: {
      items: [],
      authors: {},
      engagement: {},
      stories: [],
      story_authors: {},
      next_cursor: null,
      page_meta: { limit: 8, returned: 0, has_more: false },
      following_ids_echo: [AUTHOR_A, AUTHOR_B],
      ...overrides,
    },
  }
}

function tradeItem(id: string, authorId: string, createdAt: string): FeedItemV1 {
  return {
    kind: "post",
    id,
    created_at: createdAt,
    author_id: authorId,
    payload: {
      id,
      user_id: authorId,
      trade_id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
      created_at: createdAt,
      pnl: 120,
      rr: 2.5,
      image_url: "https://cdn.example/trade.png",
      profiles: { username: "trader_a", avatar_url: "https://cdn.example/a.jpg" },
      trades: {
        ticker: "ES",
        direction: "long",
        public_description: "Breakout",
        reels: null,
      },
    },
  }
}

function profilePostItem(id: string, authorId: string, createdAt: string): FeedItemV1 {
  return {
    kind: "profile_post",
    id,
    created_at: createdAt,
    author_id: authorId,
    payload: {
      id,
      user_id: authorId,
      content: "Market thoughts",
      image_url: null,
      created_at: createdAt,
      profiles: { username: "trader_b", avatar_url: null },
    },
  }
}

function reelItem(id: string, authorId: string, createdAt: string): FeedItemV1 {
  return {
    kind: "reel",
    id,
    created_at: createdAt,
    author_id: authorId,
    payload: {
      id,
      user_id: authorId,
      caption: "Clip",
      video_url: "https://cdn.example/v.mp4",
      thumbnail_url: "https://cdn.example/t.jpg",
      duration_seconds: 12,
      visibility: "public",
      trade_id: null,
      kind: "clip",
      created_at: createdAt,
      profiles: { username: "trader_a", avatar_url: null },
      trades: null,
    },
  }
}

function achievementItem(id: string, authorId: string, createdAt: string): FeedItemV1 {
  return {
    kind: "achievement_post",
    id,
    created_at: createdAt,
    author_id: authorId,
    payload: {
      id,
      user_id: authorId,
      achievement_id: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
      created_at: createdAt,
      metadata: {},
      achievements: { id: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", title: "Win streak" },
      profiles: { username: "trader_b", avatar_url: "https://cdn.example/b.jpg" },
    },
  }
}

function withEngagement(
  feed: FeedBootstrapV1,
  items: FeedItemV1[],
  opts?: { liked?: boolean; comments?: number; likes?: number }
): FeedBootstrapV1 {
  const engagement: FeedBootstrapV1["data"]["engagement"] = {}
  for (const item of items) {
    engagement[item.id] = {
      like_count: opts?.likes ?? 2,
      comment_count: opts?.comments ?? 1,
      liked_by_viewer: opts?.liked ?? false,
    }
  }
  const authors: FeedBootstrapV1["data"]["authors"] = {}
  for (const item of items) {
    if (!authors[item.author_id]) {
      authors[item.author_id] = authorCard(item.author_id, "trader", null)
    }
  }
  return {
    ...feed,
    data: {
      ...feed.data,
      items,
      authors,
      engagement,
      page_meta: {
        limit: 8,
        returned: items.length,
        has_more: items.length >= 8,
      },
      next_cursor:
        items.length >= 8
          ? `${items[items.length - 1].created_at}|${items[items.length - 1].kind}|${items[items.length - 1].id}`
          : null,
    },
  }
}

export const feedContractFixtures = {
  /** Global + All — mixed content types */
  globalAll: withEngagement(
    baseFeed({ scope: "global", content_filter: "all", following_ids_echo: [AUTHOR_A] }),
    [
      tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS),
      profilePostItem("22222222-2222-2222-2222-222222222222", AUTHOR_B, TS),
      reelItem("33333333-3333-3333-3333-333333333333", AUTHOR_A, TS),
      achievementItem("44444444-4444-4444-4444-444444444444", AUTHOR_B, TS),
    ]
  ),

  globalTrades: withEngagement(
    baseFeed({ scope: "global", content_filter: "trades", following_ids_echo: [AUTHOR_A] }),
    [tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS)]
  ),

  globalPosts: withEngagement(
    baseFeed({ scope: "global", content_filter: "posts", following_ids_echo: [AUTHOR_A] }),
    [profilePostItem("22222222-2222-2222-2222-222222222222", AUTHOR_B, TS)]
  ),

  globalReels: withEngagement(
    baseFeed({ scope: "global", content_filter: "reels", following_ids_echo: [AUTHOR_A] }),
    [reelItem("33333333-3333-3333-3333-333333333333", AUTHOR_A, TS)]
  ),

  globalAchievements: withEngagement(
    baseFeed({ scope: "global", content_filter: "achievements", following_ids_echo: [AUTHOR_A] }),
    [achievementItem("44444444-4444-4444-4444-444444444444", AUTHOR_B, TS)]
  ),

  followingAll: withEngagement(
    baseFeed({ scope: "following", content_filter: "all" }),
    [
      tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS),
      profilePostItem("22222222-2222-2222-2222-222222222222", AUTHOR_B, TS),
    ]
  ),

  followingTrades: withEngagement(
    baseFeed({ scope: "following", content_filter: "trades" }),
    [tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS)]
  ),

  followingPosts: withEngagement(
    baseFeed({ scope: "following", content_filter: "posts" }),
    [profilePostItem("22222222-2222-2222-2222-222222222222", AUTHOR_B, TS)]
  ),

  followingReels: withEngagement(
    baseFeed({ scope: "following", content_filter: "reels" }),
    [reelItem("33333333-3333-3333-3333-333333333333", AUTHOR_A, TS)]
  ),

  followingAchievements: withEngagement(
    baseFeed({ scope: "following", content_filter: "achievements" }),
    [achievementItem("44444444-4444-4444-4444-444444444444", AUTHOR_B, TS)]
  ),

  emptyFollowing: baseFeed({
    scope: "following",
    content_filter: "all",
    following_ids_echo: [],
  }),

  /** Equal timestamps — keyset cursor must use kind|id tie-breakers */
  equalTimestampBoundary: withEngagement(
    baseFeed({ scope: "following", content_filter: "all" }),
    [
      tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS_EQUAL),
      profilePostItem("22222222-2222-2222-2222-222222222222", AUTHOR_B, TS_EQUAL),
      reelItem("33333333-3333-3333-3333-333333333333", AUTHOR_A, TS_EQUAL),
    ]
  ),

  paginationBoundary: (() => {
    const items = Array.from({ length: 8 }, (_, i) =>
      tradeItem(
        `${String(i).padStart(8, "0")}-1111-1111-1111-111111111111`.slice(0, 36),
        AUTHOR_A,
        `2026-08-20T10:0${i}:00.000Z`
      )
    )
    return withEngagement(
      baseFeed({ scope: "following", content_filter: "trades" }),
      items
    )
  })(),

  withStories: {
    ...withEngagement(
      baseFeed({ scope: "following", content_filter: "all" }),
      [tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS)]
    ),
    data: {
      ...withEngagement(
        baseFeed({ scope: "following", content_filter: "all" }),
        [tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS)]
      ).data,
      stories: [
        {
          id: "55555555-5555-5555-5555-555555555555",
          user_id: AUTHOR_A,
          image_url: "https://cdn.example/story.jpg",
          created_at: TS,
        },
      ],
      story_authors: {
        [AUTHOR_A]: authorCard(AUTHOR_A, "trader_a", "https://cdn.example/a.jpg"),
      },
    },
  } satisfies FeedBootstrapV1,

  viewerLikedCommented: (() => {
    const feed = withEngagement(
      baseFeed({ scope: "following", content_filter: "all" }),
      [tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS)],
      { liked: true, comments: 5, likes: 10 }
    )
    return feed
  })(),

  noAvatarNoScreenshot: withEngagement(
    baseFeed({ scope: "global", content_filter: "posts", following_ids_echo: [] }),
    [
      {
        kind: "profile_post",
        id: "22222222-2222-2222-2222-222222222222",
        created_at: TS,
        author_id: AUTHOR_B,
        payload: {
          id: "22222222-2222-2222-2222-222222222222",
          user_id: AUTHOR_B,
          content: "Text only",
          image_url: null,
          created_at: TS,
          profiles: { username: "no_avatar", avatar_url: null },
        },
      },
    ]
  ),

  linkedTradeReel: withEngagement(
    baseFeed({ scope: "following", content_filter: "trades" }),
    [
      {
        ...tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS),
        payload: {
          ...tradeItem("11111111-1111-1111-1111-111111111111", AUTHOR_A, TS).payload,
          trades: {
            ticker: "NQ",
            direction: "short",
            public_description: "With reel",
            reels: {
              id: "66666666-6666-6666-6666-666666666666",
              user_id: AUTHOR_A,
              video_url: "https://cdn.example/v.mp4",
              thumbnail_url: "https://cdn.example/t.jpg",
              duration_seconds: 8,
              trade_id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
              visibility: "public",
            },
          },
        },
      },
    ]
  ),
}

export type FeedContractFixtureName = keyof typeof feedContractFixtures
