export type GettingStartedChecklistItemId =
  | "profile"
  | "trade"
  | "post"
  | "follow"
  | "room"

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
  joinedOtherRoom: boolean
}

export type GettingStartedProgress = {
  items: GettingStartedChecklistItem[]
  completedCount: number
  totalCount: number
  allComplete: boolean
}

const TOTAL_ITEMS = 5

export const GETTING_STARTED_COLLAPSED_STORAGE_KEY =
  "tradetraxs_getting_started_collapsed_v1"

export function readGettingStartedCollapsedPreference(): boolean {
  if (typeof window === "undefined") return false
  try {
    return window.localStorage.getItem(GETTING_STARTED_COLLAPSED_STORAGE_KEY) === "1"
  } catch {
    return false
  }
}

export function writeGettingStartedCollapsedPreference(collapsed: boolean) {
  if (typeof window === "undefined") return
  try {
    if (collapsed) {
      window.localStorage.setItem(GETTING_STARTED_COLLAPSED_STORAGE_KEY, "1")
    } else {
      window.localStorage.removeItem(GETTING_STARTED_COLLAPSED_STORAGE_KEY)
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
      complete: signals.joinedOtherRoom,
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

/** Show card when onboarding path or any checklist item remains incomplete. */
export function shouldShowGettingStartedCard(
  hasNoTrades: boolean,
  allComplete: boolean
): boolean {
  return hasNoTrades || !allComplete
}
