import { shouldShowGettingStartedSection } from "@/lib/gettingStartedSticky"

export type GettingStartedChecklistItemId =
  | "profile"
  | "trade"
  | "post"
  | "follow"
  | "room"
  | "public"

export type GettingStartedChecklistItem = {
  id: GettingStartedChecklistItemId
  label: string
  complete: boolean
}

export type GettingStartedSignals = {
  onboardingCompleted: boolean
  tradeCount: number
  profilePostCount: number
  feedPostCount: number
  followCount: number
  /** Ever joined a room the user does not own (includes left memberships). */
  hasEverJoinedOtherRoom: boolean
  hasPublicTrade: boolean
}

export type GettingStartedItemHelp = {
  body: string
}

export const GETTING_STARTED_ITEM_HELP: Record<
  GettingStartedChecklistItemId,
  GettingStartedItemHelp
> = {
  profile: {
    body:
      "You already completed this during onboarding. Your profile helps other traders discover you and see your trading journey.",
  },
  trade: {
    body:
      "Click Add Trade and enter your entry, exit, and result. Your dashboard analytics unlock after your first trade.",
  },
  follow: {
    body:
      "Visit Explore and click Follow on a trader. Their trades, posts, and activity will start appearing in your feed.",
  },
  room: {
    body:
      "Trade Rooms are communities where traders share ideas, charts, setups, and market discussions. Many traders also showcase their rooms directly on their profiles. Click this task to browse popular rooms and join one.",
  },
  post: {
    body:
      "Click this task to go to your profile and open the post creator.\n\nShare a trade, chart, lesson learned, or market idea with the community. Posts appear on your profile and in the feed.",
  },
  public: {
    body:
      "Open one of your trades and enable the Public setting. Public trades can appear on your profile, the feed, and the leaderboard.",
  },
}

export type GettingStartedProgress = {
  items: GettingStartedChecklistItem[]
  completedCount: number
  totalCount: number
  allComplete: boolean
}

const TOTAL_ITEMS = 6

export const GETTING_STARTED_COLLAPSED_STORAGE_KEY =
  "tradetraxs_getting_started_collapsed_v1"

function collapsedStorageKey(userId: string): string {
  return `${GETTING_STARTED_COLLAPSED_STORAGE_KEY}:${userId}`
}

export function readGettingStartedCollapsedPreference(userId: string): boolean {
  if (typeof window === "undefined") return false
  try {
    return (
      window.localStorage.getItem(collapsedStorageKey(userId)) === "1"
    )
  } catch {
    return false
  }
}

export function writeGettingStartedCollapsedPreference(
  userId: string,
  collapsed: boolean
) {
  if (typeof window === "undefined") return
  try {
    if (collapsed) {
      window.localStorage.setItem(collapsedStorageKey(userId), "1")
    } else {
      window.localStorage.removeItem(collapsedStorageKey(userId))
    }
  } catch {
    /* ignore quota / private mode */
  }
}

export function computeGettingStartedProgress(
  signals: GettingStartedSignals
): GettingStartedProgress {
  const hasPost =
    signals.profilePostCount > 0 || signals.feedPostCount > 0

  const items: GettingStartedChecklistItem[] = [
    {
      id: "profile",
      label: "Complete your profile",
      complete: signals.onboardingCompleted,
    },
    {
      id: "trade",
      label: "Log your first trade",
      complete: signals.tradeCount > 0,
    },
    {
      id: "post",
      label: "Create your first post",
      complete: hasPost,
    },
    {
      id: "follow",
      label: "Follow another trader",
      complete: signals.followCount > 0,
    },
    {
      id: "room",
      label: "Join a trade room",
      complete: signals.hasEverJoinedOtherRoom,
    },
    {
      id: "public",
      label: "Make Your First Trade Public",
      complete: signals.hasPublicTrade,
    },
  ]

  const completedCount = items.filter((item) => item.complete).length

  return {
    items,
    completedCount,
    totalCount: TOTAL_ITEMS,
    allComplete: completedCount === TOTAL_ITEMS,
  }
}

export { shouldShowGettingStartedSection }
