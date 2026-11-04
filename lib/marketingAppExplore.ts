/**
 * Marketing homepage → real in-app routes with guest showcase session.
 * Uses {@link enterGuestExplore} — not bundled `/demo/*` mock routes.
 */

import { disableDemoMode, exitDemoMode } from "@/lib/demo/demoMode"
import { enterGuestExplore, isGuestExploreActive } from "@/lib/guestExplore"
import { supabase } from "@/lib/supabaseClient"

export type MarketingAppDestinationId =
  | "analytics"
  | "journal"
  | "feed"
  | "rooms"
  | "messages"
  | "profiles"
  | "psychology"
  | "propfirm"
  | "achievements"
  | "leaderboard"

export type MarketingAppDestination = {
  id: MarketingAppDestinationId
  path: string
  exploreLabel: string
}

export const MARKETING_APP_DESTINATIONS: Record<
  MarketingAppDestinationId,
  MarketingAppDestination
> = {
  analytics: {
    id: "analytics",
    path: "/dashboard",
    exploreLabel: "Explore Analytics",
  },
  journal: {
    id: "journal",
    path: "/dashboard",
    exploreLabel: "Explore the Journal",
  },
  feed: {
    id: "feed",
    path: "/feed",
    exploreLabel: "Explore the Feed",
  },
  rooms: {
    id: "rooms",
    path: "/community",
    exploreLabel: "Explore Trade Rooms",
  },
  messages: {
    id: "messages",
    path: "/messages",
    exploreLabel: "Explore Messages",
  },
  profiles: {
    id: "profiles",
    path: "/explore",
    exploreLabel: "Explore Trader Profiles",
  },
  psychology: {
    id: "psychology",
    path: "/check-in-history",
    exploreLabel: "Explore Check-Ins",
  },
  propfirm: {
    id: "propfirm",
    path: "/analytics/propfirm",
    exploreLabel: "Explore Prop Firm Tracking",
  },
  achievements: {
    id: "achievements",
    path: "/achievements",
    exploreLabel: "Explore Achievements",
  },
  leaderboard: {
    id: "leaderboard",
    path: "/leaderboard",
    exploreLabel: "View Leaderboard",
  },
}

/**
 * Open a real app route. Installs guest showcase session when logged out;
 * clears bundled demo mode so the live app is used.
 */
export async function navigateMarketingAppExplore(
  destination: MarketingAppDestinationId
): Promise<{ ok: true } | { ok: false }> {
  if (typeof window === "undefined") return { ok: false }

  const path = MARKETING_APP_DESTINATIONS[destination].path
  exitDemoMode()
  disableDemoMode()

  const { data } = await supabase.auth.getSession()
  const userId = data.session?.user?.id ?? null

  if (userId || isGuestExploreActive()) {
    window.location.assign(path)
    return { ok: true }
  }

  const result = await enterGuestExplore()
  if (!result.ok) {
    return { ok: false }
  }

  window.location.assign(path)
  return { ok: true }
}
