export type GettingStartedChecklistItemId =
  | "profile"
  | "account"
  | "trade"
  | "ai_analysis"
  | "room"
  | "post"
  | "follow"
  | "public"

export type GettingStartedChecklistItem = {
  id: GettingStartedChecklistItemId
  label: string
  complete: boolean
}

export type GettingStartedSignals = {
  onboardingCompleted: boolean
  accountCount: number
  tradeCount: number
  hasRunAiAnalysis: boolean
  /** Ever joined a room the user does not own (includes left memberships). */
  hasEverJoinedOtherRoom: boolean
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
      "Add your username, display name, and trader details in Settings so other traders can discover you.",
  },
  account: {
    body:
      "Create a trading account in Settings so trades are organized by account type, size, and prop firm rules.",
  },
  trade: {
    body:
      "Click Add Trade and enter your entry, exit, and result. Your dashboard analytics unlock after your first trade.",
  },
  ai_analysis: {
    body:
      "Open AI Analyst, pick a trade, and run your first analysis to get structured feedback on your execution.",
  },
  room: {
    body:
      "Trade Rooms are communities where traders share ideas, charts, setups, and market discussions. Click this task to browse popular rooms and join one.",
  },
  follow: {
    body:
      "Visit Explore and click Follow on a trader. Their trades, posts, and activity will start appearing in your feed.",
  },
  post: {
    body:
      "Click this task to go to your profile and open the post creator.\n\nShare a chart, lesson learned, or market idea with the community. Posts appear on your profile and in the feed.",
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

const TOTAL_ITEMS = 5

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

const SESSION_DISMISS_STORAGE_KEY =
  "tradetraxs_getting_started_dismissed_session_v1"

function sessionDismissStorageKey(userId: string): string {
  return `${SESSION_DISMISS_STORAGE_KEY}:${userId}`
}

/** True when the user collapsed/closed the checklist this browser session. */
export function readGettingStartedSessionDismissed(userId: string): boolean {
  if (typeof window === "undefined") return false
  try {
    return (
      window.sessionStorage.getItem(sessionDismissStorageKey(userId)) === "1"
    )
  } catch {
    return false
  }
}

export function writeGettingStartedSessionDismissed(userId: string) {
  if (typeof window === "undefined") return
  try {
    window.sessionStorage.setItem(sessionDismissStorageKey(userId), "1")
  } catch {
    /* ignore quota / private mode */
  }
}

/** Intro popup is never shown automatically — onboarding_completed gates all auto UI. */
export function shouldShowGettingStartedIntroPopup(_options: {
  onboardingCompleted: boolean
  hasSeenGettingStartedIntro: boolean
}): boolean {
  return false
}

/** Whether the checklist can be opened manually (navbar mobile entry, etc.). */
export function shouldOfferGettingStartedChecklist(
  userId: string | null | undefined,
  options: {
    hasSeenOnboardingCompletePopup: boolean
    allComplete: boolean
  }
): boolean {
  return Boolean(
    userId &&
      !options.hasSeenOnboardingCompletePopup &&
      !options.allComplete
  )
}

/**
 * Whether the dashboard should embed the checklist automatically.
 * Show after profile onboarding is complete while getting-started tasks remain.
 */
export function shouldAutoShowGettingStartedChecklist(
  userId: string | null | undefined,
  options: {
    onboardingCompleted: boolean
    allComplete?: boolean
    hasSeenOnboardingCompletePopup?: boolean
  }
): boolean {
  if (!userId || !options.onboardingCompleted) {
    return false
  }

  if (options.allComplete || options.hasSeenOnboardingCompletePopup) {
    return false
  }

  if (readGettingStartedSessionDismissed(userId)) {
    return false
  }

  return true
}

/** @deprecated Use shouldOfferGettingStartedChecklist or shouldAutoShowGettingStartedChecklist */
export function shouldShowGettingStartedChecklist(
  userId: string | null | undefined,
  options: {
    hasSeenOnboardingCompletePopup: boolean
    allComplete: boolean
  }
): boolean {
  return shouldOfferGettingStartedChecklist(userId, options)
}

export function computeGettingStartedProgress(
  signals: GettingStartedSignals
): GettingStartedProgress {
  const items: GettingStartedChecklistItem[] = [
    {
      id: "profile",
      label: "Complete your profile",
      complete: signals.onboardingCompleted,
    },
    {
      id: "account",
      label: "Add your first trading account",
      complete: signals.accountCount > 0,
    },
    {
      id: "trade",
      label: "Add your first trade",
      complete: signals.tradeCount > 0,
    },
    {
      id: "ai_analysis",
      label: "Run your first AI analysis",
      complete: signals.hasRunAiAnalysis,
    },
    {
      id: "room",
      label: "Join a trade room",
      complete: signals.hasEverJoinedOtherRoom,
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

/** Tasks that flipped incomplete → complete between two progress snapshots. */
export function detectNewlyCompletedTasks(
  previous: GettingStartedProgress | null,
  next: GettingStartedProgress
): GettingStartedChecklistItem[] {
  if (!previous) return []
  const newly: GettingStartedChecklistItem[] = []
  for (const item of next.items) {
    const prior = previous.items.find((row) => row.id === item.id)
    if (item.complete && !prior?.complete) {
      newly.push(item)
    }
  }
  return newly
}
