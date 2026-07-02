import type { Achievement } from "@/lib/achievementTypes"
import type { ReelRow } from "@/lib/reels"
import type { FollowUiSnapshot } from "@/lib/followActions"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import { isProfileUuidSegment } from "@/lib/profileRoutes"
import { DEMO_USER_ID } from "./constants"
import { DEMO_FOLLOWERS, DEMO_PROFILE, DEMO_TRADES } from "./fixtures"
import {
  DEMO_FOLLOWING_IDS,
  DEMO_USER_ALEX,
  DEMO_USER_ELI,
  DEMO_USER_JORDAN,
  DEMO_USER_MIKE,
  DEMO_USER_SARAH,
} from "./demoFeed"
import { demoAvatarUrl, demoReelThumbnailUrl, demoRoomImageUrl } from "./demoAvatars"
import { demoPostImageUrl, demoTradeScreenshotUrl } from "./demoAssets"
import {
  getDemoAchievementsForUser,
  getDemoPublicAchievementsForUser,
} from "./demoAchievements"
import { isoDemoDaysAgo } from "./demoTime"

export type DemoPublicProfile = {
  id: string
  username: string
  name: string
  bio: string | null
  avatar_url: string | null
  trading_style: string | null
  trader_type: string | null
  primary_market: string | null
  started_trading: string | null
  is_private: boolean
  created_at: string
}

const DEMO_USER_REGISTRY: DemoPublicProfile[] = [
  {
    id: DEMO_USER_ID,
    username: DEMO_PROFILE.username,
    name: DEMO_PROFILE.name,
    bio: DEMO_PROFILE.bio,
    avatar_url: demoAvatarUrl(DEMO_USER_ID),
    trading_style: DEMO_PROFILE.trading_style,
    trader_type: DEMO_PROFILE.trader_type,
    primary_market: DEMO_PROFILE.primary_market,
    started_trading: DEMO_PROFILE.started_trading,
    is_private: DEMO_PROFILE.is_private,
    created_at: isoDemoDaysAgo(400, 8),
  },
  {
    id: DEMO_USER_ALEX,
    username: "alex_futures",
    name: "Alex Rivera",
    bio: "ES/NQ day trader. Prop firm funded. Sharing setups in Trade Rooms daily.",
    avatar_url: demoAvatarUrl(DEMO_USER_ALEX),
    trading_style: "Day Trading",
    trader_type: "Futures",
    primary_market: "US Indices",
    started_trading: "2019",
    is_private: false,
    created_at: isoDemoDaysAgo(500, 9),
  },
  {
    id: DEMO_USER_JORDAN,
    username: "jordan_scalps",
    name: "Jordan Lee",
    bio: "Scalper on NQ. Process over P&L.",
    avatar_url: demoAvatarUrl(DEMO_USER_JORDAN),
    trading_style: "Scalping",
    trader_type: "Futures",
    primary_market: "US Indices",
    started_trading: "2020",
    is_private: false,
    created_at: isoDemoDaysAgo(450, 10),
  },
  {
    id: DEMO_USER_SARAH,
    username: "sarah_indices",
    name: "Sarah Kim",
    bio: "Index futures + journaling advocate. Prop firm mode power user.",
    avatar_url: demoAvatarUrl(DEMO_USER_SARAH),
    trading_style: "Day Trading",
    trader_type: "Futures",
    primary_market: "US Indices",
    started_trading: "2022",
    is_private: false,
    created_at: isoDemoDaysAgo(380, 11),
  },
  {
    id: DEMO_USER_MIKE,
    username: "mike_swings",
    name: "Mike Ortiz",
    bio: "Swing trader on equities. Longer holds, tighter filters.",
    avatar_url: demoAvatarUrl(DEMO_USER_MIKE),
    trading_style: "Swing Trading",
    trader_type: "Stocks",
    primary_market: "US Equities",
    started_trading: "2018",
    is_private: false,
    created_at: isoDemoDaysAgo(600, 12),
  },
  {
    id: DEMO_USER_ELI,
    username: "eli_prop",
    name: "Eli Nguyen",
    bio: "Documenting the prop firm journey — evals, payouts, and rule tracking.",
    avatar_url: demoAvatarUrl(DEMO_USER_ELI),
    trading_style: "Day Trading",
    trader_type: "Futures",
    primary_market: "US Indices",
    started_trading: "2023",
    is_private: false,
    created_at: isoDemoDaysAgo(200, 13),
  },
]

const DEMO_USERS_BY_ID = new Map(
  DEMO_USER_REGISTRY.map((row) => [row.id, row])
)
const DEMO_USERS_BY_USERNAME = new Map(
  DEMO_USER_REGISTRY.map((row) => [row.username.toLowerCase(), row])
)

export const DEMO_MAYA_ROOM = {
  id: "demo-room-maya",
  name: "Maya's Morning Desk",
  description: "Live commentary and same-day trade reviews during the US open.",
  slug: "maya-morning-desk",
  image_url: demoRoomImageUrl("demo-room-maya"),
  owner_user_id: DEMO_USER_ID,
  show_on_profile: true,
}

const DEMO_FOLLOWERS_BY_PROFILE: Record<string, string[]> = {
  [DEMO_USER_ID]: [
    DEMO_USER_ALEX,
    DEMO_USER_JORDAN,
    DEMO_USER_SARAH,
    DEMO_USER_MIKE,
    DEMO_USER_ELI,
  ],
  [DEMO_USER_ALEX]: [DEMO_USER_ID, DEMO_USER_JORDAN, DEMO_USER_SARAH],
  [DEMO_USER_JORDAN]: [DEMO_USER_ID, DEMO_USER_ALEX],
  [DEMO_USER_SARAH]: [DEMO_USER_ID, DEMO_USER_MIKE],
}

const DEMO_FOLLOWING_BY_PROFILE: Record<string, string[]> = {
  [DEMO_USER_ID]: [...DEMO_FOLLOWING_IDS],
  [DEMO_USER_ALEX]: [DEMO_USER_ID, DEMO_USER_JORDAN],
  [DEMO_USER_JORDAN]: [DEMO_USER_ID, DEMO_USER_ALEX, DEMO_USER_SARAH],
}

const PUBLIC_TRADE_IDS = new Set([
  "dt-24",
  "dt-23",
  "dt-21",
  "dt-17",
  "dt-13",
  "dt-09",
  "dt-07",
  "dt-03",
])

const DEMO_REELS: ReelRow[] = [
  {
    id: "demo-reel-1",
    user_id: DEMO_USER_ID,
    caption: null,
    video_url:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    thumbnail_url: demoReelThumbnailUrl("demo-reel-1"),
    duration_seconds: 42,
    visibility: "public",
    trade_id: "dt-03",
    kind: null,
    created_at: isoDemoDaysAgo(1, 15),
    updated_at: isoDemoDaysAgo(1, 15),
    trades: {
      id: "dt-03",
      public_description: "Clean NQ continuation after liquidity sweep — held to target.",
      is_public: true,
      ticker: "NQ",
      direction: "Long",
      pnl: 1260,
      rr: 3.2,
    },
  },
  {
    id: "demo-reel-maya-2",
    user_id: DEMO_USER_ID,
    caption: "How I Passed My Eval — rule tracking workflow",
    video_url:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
    thumbnail_url: demoReelThumbnailUrl("demo-reel-maya-2"),
    duration_seconds: 75,
    visibility: "public",
    trade_id: null,
    kind: null,
    created_at: isoDemoDaysAgo(8, 10),
    updated_at: isoDemoDaysAgo(8, 10),
  },
  {
    id: "demo-reel-maya-3",
    user_id: DEMO_USER_ID,
    caption: "3 Mistakes From Last Week — journal review",
    video_url:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
    thumbnail_url: demoReelThumbnailUrl("demo-reel-maya-3"),
    duration_seconds: 58,
    visibility: "public",
    trade_id: null,
    kind: null,
    created_at: isoDemoDaysAgo(14, 11),
    updated_at: isoDemoDaysAgo(14, 11),
  },
  {
    id: "demo-reel-2",
    user_id: DEMO_USER_ALEX,
    caption: "ES Reversal Play — overnight high rejection",
    video_url:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    thumbnail_url: demoReelThumbnailUrl("demo-reel-2"),
    duration_seconds: 55,
    visibility: "public",
    trade_id: null,
    kind: null,
    created_at: isoDemoDaysAgo(3, 10),
    updated_at: isoDemoDaysAgo(3, 10),
  },
  {
    id: "demo-reel-alex-2",
    user_id: DEMO_USER_ALEX,
    caption: "Pre-market levels I watch every session",
    video_url:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
    thumbnail_url: demoReelThumbnailUrl("demo-reel-alex-2"),
    duration_seconds: 48,
    visibility: "public",
    trade_id: null,
    kind: null,
    created_at: isoDemoDaysAgo(10, 9),
    updated_at: isoDemoDaysAgo(10, 9),
  },
]

const DEMO_WALL_POSTS: Record<string, Record<string, unknown>[]> = {
  [DEMO_USER_ID]: [
    {
      id: "demo-wall-maya-1",
      user_id: DEMO_USER_ID,
      content:
        "Green week on the eval — consistency rule was the hardest part. Prop Firm Mode made tracking winning days painless.",
      image_url: demoPostImageUrl("demo-wall-maya-1"),
      room_id: null,
      created_at: isoDemoDaysAgo(2, 16),
    },
    {
      id: "demo-wall-maya-2",
      user_id: DEMO_USER_ID,
      content: "Join us for live commentary during the US open.",
      image_url: null,
      room_id: DEMO_MAYA_ROOM.id,
      created_at: isoDemoDaysAgo(5, 7),
    },
    {
      id: "demo-wall-maya-3",
      user_id: DEMO_USER_ID,
      content:
        "Posted today's NQ long breakdown on the feed — liquidity sweep + 1m BOS. Link in reels tab too.",
      image_url: demoTradeScreenshotUrl("dt-24", { direction: "Long", pnl: 1050 }),
      room_id: null,
      created_at: isoDemoDaysAgo(0, 11),
    },
  ],
  [DEMO_USER_ALEX]: [
    {
      id: "demo-wall-alex-1",
      user_id: DEMO_USER_ALEX,
      content:
        "Who else is watching NQ into CPI tomorrow? Planning to size down and wait for the first 15m structure.",
      image_url: demoPostImageUrl("demo-wall-alex-1"),
      room_id: null,
      created_at: isoDemoDaysAgo(0, 8),
    },
    {
      id: "demo-wall-alex-2",
      user_id: DEMO_USER_ALEX,
      content: "ES reversal from overnight high — full chart markup in today's reel.",
      image_url: demoTradeScreenshotUrl("demo-trade-alex-1", { direction: "Short", pnl: 720 }),
      room_id: null,
      created_at: isoDemoDaysAgo(1, 14),
    },
  ],
  [DEMO_USER_SARAH]: [
    {
      id: "demo-wall-sarah-1",
      user_id: DEMO_USER_SARAH,
      content:
        "Five winning days on eval — Prop Firm Mode tracking made the consistency rule manageable.",
      image_url: demoPostImageUrl("demo-wall-sarah-1"),
      room_id: null,
      created_at: isoDemoDaysAgo(1, 16),
    },
  ],
}

export function isDemoProfileId(profileId: string | null | undefined): boolean {
  return profileId != null && DEMO_USERS_BY_ID.has(profileId)
}

export function resolveDemoProfileBySegment(
  segment: string
): DemoPublicProfile | null {
  const trimmed = segment.trim()
  if (!trimmed) return null
  if (isProfileUuidSegment(trimmed)) {
    return DEMO_USERS_BY_ID.get(trimmed) ?? null
  }
  return (
    DEMO_USERS_BY_USERNAME.get(normalizeProfileUsername(trimmed).toLowerCase()) ??
    null
  )
}

export function getDemoProfileById(
  profileId: string
): DemoPublicProfile | null {
  return DEMO_USERS_BY_ID.get(profileId) ?? null
}

export function getDemoProfileList(): DemoPublicProfile[] {
  return [...DEMO_USER_REGISTRY]
}

export function getDemoFollowUiSnapshot(
  viewerId: string | null | undefined,
  profileUserId: string
): FollowUiSnapshot {
  if (!viewerId || viewerId === profileUserId) {
    return { state: "none", followsYou: false }
  }
  const following = (DEMO_FOLLOWING_BY_PROFILE[viewerId] ?? []).includes(
    profileUserId
  )
  const followsYou = (DEMO_FOLLOWERS_BY_PROFILE[profileUserId] ?? []).includes(
    viewerId
  )
  return {
    state: following ? "following" : "none",
    followsYou,
  }
}

export function getDemoProfileMetadata(
  profileId: string,
  viewerId: string | null
) {
  const profile = getDemoProfileById(profileId)
  if (!profile) return null

  const snapshot = getDemoFollowUiSnapshot(viewerId, profileId)
  const room =
    profileId === DEMO_USER_ID ? DEMO_MAYA_ROOM : null

  const followersN =
    profileId === DEMO_USER_ID
      ? DEMO_FOLLOWERS.followers
      : (DEMO_FOLLOWERS_BY_PROFILE[profileId]?.length ?? 24)
  const followingN =
    profileId === DEMO_USER_ID
      ? DEMO_FOLLOWERS.following
      : (DEMO_FOLLOWING_BY_PROFILE[profileId]?.length ?? 12)

  return {
    following: snapshot.state === "following",
    requested: false,
    profileFollowsYou: snapshot.followsYou,
    roomRow: room,
    followersN,
    followingN,
  }
}

export function getDemoProfileTrades(
  profileId: string,
  _viewerId: string | null
): Record<string, unknown>[] {
  if (profileId !== DEMO_USER_ID) return []
  return DEMO_TRADES.filter((t) => PUBLIC_TRADE_IDS.has(t.id)).map((t) => ({
    ...t,
    is_public: true,
  }))
}

export function getDemoProfileWallPosts(profileId: string) {
  return DEMO_WALL_POSTS[profileId] ?? []
}

export function getDemoProfileReels(profileId: string): ReelRow[] {
  return DEMO_REELS.filter((r) => r.user_id === profileId)
}

export function getDemoReelsByTradeIds(
  profileId: string,
  tradeIds: string[]
): Map<string, ReelRow> {
  const idSet = new Set(tradeIds.map(String))
  const map = new Map<string, ReelRow>()
  for (const reel of getDemoProfileReels(profileId)) {
    if (reel.trade_id && idSet.has(String(reel.trade_id))) {
      map.set(String(reel.trade_id), reel)
    }
  }
  return map
}

export function getDemoProfileAchievements(
  profileId: string,
  isOwner: boolean
): Achievement[] {
  if (isOwner) return getDemoAchievementsForUser(profileId)
  return getDemoPublicAchievementsForUser(profileId)
}

export function getDemoFollowersModalUsers(profileId: string) {
  const ids = DEMO_FOLLOWERS_BY_PROFILE[profileId] ?? []
  return ids
    .map((id) => getDemoProfileById(id))
    .filter(Boolean)
    .map((p) => ({
      id: p!.id,
      username: p!.username,
      avatar_url: p!.avatar_url,
      name: p!.name,
    }))
}

export function getDemoFollowingModalUsers(profileId: string) {
  const ids = DEMO_FOLLOWING_BY_PROFILE[profileId] ?? DEMO_FOLLOWING_IDS
  return ids
    .map((id) => getDemoProfileById(id))
    .filter(Boolean)
    .map((p) => ({
      id: p!.id,
      username: p!.username,
      avatar_url: p!.avatar_url,
      name: p!.name,
    }))
}

export function getDemoProfileFollowingIds(viewerId: string): string[] {
  return DEMO_FOLLOWING_BY_PROFILE[viewerId] ?? DEMO_FOLLOWING_IDS
}
