import type { ExploreProfile, ExploreTopView } from "@/lib/exploreDiscover"
import type { TradeForLeaderboard } from "@/lib/leaderboardChart"
import { filterTradesForLeaderboardWindow } from "@/lib/leaderboardChart"
import { DEMO_USER_ID } from "./constants"
import {
  DEMO_FOLLOWING_IDS,
  DEMO_USER_ALEX,
  DEMO_USER_ELI,
  DEMO_USER_JORDAN,
  DEMO_USER_MIKE,
  DEMO_USER_SARAH,
} from "./demoFeed"
import { DEMO_FOLLOWERS, DEMO_TRADES } from "./fixtures"
import { getDemoProfileList } from "./demoProfile"
import { getDemoLeaderboardTrades } from "./demoLeaderboard"

const DEMO_SOCIAL_COUNTS: Record<
  string,
  { followers: number; following: number }
> = {
  [DEMO_USER_ID]: {
    followers: DEMO_FOLLOWERS.followers,
    following: DEMO_FOLLOWERS.following,
  },
  [DEMO_USER_ALEX]: { followers: 842, following: 124 },
  [DEMO_USER_JORDAN]: { followers: 1205, following: 98 },
  [DEMO_USER_SARAH]: { followers: 634, following: 156 },
  [DEMO_USER_MIKE]: { followers: 412, following: 88 },
  [DEMO_USER_ELI]: { followers: 289, following: 64 },
}

export function getDemoExploreProfiles(): ExploreProfile[] {
  return getDemoProfileList().map((profile) => {
    const social = DEMO_SOCIAL_COUNTS[profile.id]
    return {
      id: profile.id,
      username: profile.username,
      name: profile.name,
      avatar_url: profile.avatar_url,
      bio: profile.bio,
      created_at: profile.created_at,
      is_private: profile.is_private,
      trader_type: profile.trader_type,
      trading_style: profile.trading_style,
      primary_market: profile.primary_market,
      started_trading: profile.started_trading,
      followers_count: social?.followers ?? 0,
      following_count: social?.following ?? 0,
    }
  })
}

export function getDemoExploreFollowingIds(viewerId: string | null): string[] {
  if (!viewerId || viewerId !== DEMO_USER_ID) return []
  return [...DEMO_FOLLOWING_IDS]
}

export function getDemoExploreFollowsYouIds(viewerId: string | null): string[] {
  if (!viewerId) return []
  return [
    DEMO_USER_ALEX,
    DEMO_USER_JORDAN,
    DEMO_USER_SARAH,
    DEMO_USER_MIKE,
    DEMO_USER_ELI,
  ]
}

export function getDemoExploreTradesForView(
  view: ExploreTopView
): TradeForLeaderboard[] {
  return filterTradesForLeaderboardWindow(getDemoLeaderboardTrades(), view)
}

export function getDemoExploreTradeMetaRows(): {
  user_id: string
  session?: string | null
  ticker?: string | null
}[] {
  const fromMaya = DEMO_TRADES.filter((t) => t.is_public).map((t) => ({
    user_id: DEMO_USER_ID,
    session: t.session ?? "NY",
    ticker: t.ticker,
  }))

  const synthetic = getDemoLeaderboardTrades().map((t) => ({
    user_id: t.user_id,
    session: "NY" as const,
    ticker: "NQ",
  }))

  return [...fromMaya, ...synthetic]
}

export function searchDemoExploreProfiles(term: string): ExploreProfile[] {
  const q = term.trim().toLowerCase()
  if (q.length < 2) return []
  return getDemoExploreProfiles().filter(
    (profile) =>
      profile.username?.toLowerCase().includes(q) ||
      profile.name?.toLowerCase().includes(q)
  )
}
