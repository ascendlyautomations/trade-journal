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
import { getDemoProfileList } from "./demoProfile"
import { getDemoLeaderboardTrades } from "./demoLeaderboard"

export function getDemoExploreProfiles(): ExploreProfile[] {
  return getDemoProfileList().map((profile) => ({
    id: profile.id,
    username: profile.username,
    name: profile.name,
    avatar_url: profile.avatar_url,
    bio: profile.bio,
    created_at: profile.created_at,
    is_private: profile.is_private,
  }))
}

export function getDemoExploreFollowingIds(viewerId: string | null): string[] {
  if (!viewerId || viewerId !== DEMO_USER_ID) return []
  return [...DEMO_FOLLOWING_IDS]
}

export function getDemoExploreFollowsYouIds(viewerId: string | null): string[] {
  if (!viewerId) return []
  return [DEMO_USER_ALEX, DEMO_USER_JORDAN, DEMO_USER_SARAH, DEMO_USER_MIKE, DEMO_USER_ELI]
}

export function getDemoExploreTradesForView(
  view: ExploreTopView
): TradeForLeaderboard[] {
  return filterTradesForLeaderboardWindow(getDemoLeaderboardTrades(), view)
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
