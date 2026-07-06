export type MilestoneSignals = {
  onboardingCompleted: boolean
  tradeCount: number
  publicTradeCount: number
  profilePostCount: number
  reelCount: number
  commentCount: number
  likesReceivedCount: number
}

export type SystemMilestoneId =
  | "first_trade"
  | "trades_10"
  | "trades_100"
  | "trades_500"
  | "trades_1000"
  | "profile_completed"
  | "onboarding_completed"
  | "likes_100"
  | "first_public_trade"
  | "first_reel"
  | "first_comment"

export type SystemMilestone = {
  id: SystemMilestoneId
  title: string
  description: string
  icon: string
  isUnlocked: (signals: MilestoneSignals) => boolean
}

const STICKY_STORAGE_KEY = "tradetraxs_system_milestones_unlocked_v1"

export const SYSTEM_MILESTONES: readonly SystemMilestone[] = [
  {
    id: "first_trade",
    title: "First Trade",
    description: "Logged your first trade in TradeTraxs.",
    icon: "🎯",
    isUnlocked: (s) => s.tradeCount >= 1,
  },
  {
    id: "trades_10",
    title: "10 Trades Logged",
    description: "Built the habit with ten logged trades.",
    icon: "📓",
    isUnlocked: (s) => s.tradeCount >= 10,
  },
  {
    id: "trades_100",
    title: "100 Trades Logged",
    description: "Consistency compounds — one hundred trades logged.",
    icon: "📊",
    isUnlocked: (s) => s.tradeCount >= 100,
  },
  {
    id: "trades_500",
    title: "500 Trades Logged",
    description: "Five hundred trades in the journal.",
    icon: "🏅",
    isUnlocked: (s) => s.tradeCount >= 500,
  },
  {
    id: "trades_1000",
    title: "1000 Trades Logged",
    description: "A thousand-trade journal — elite consistency.",
    icon: "💎",
    isUnlocked: (s) => s.tradeCount >= 1000,
  },
  {
    id: "profile_completed",
    title: "Profile Completed",
    description: "Your trader profile is set up and ready to share.",
    icon: "👤",
    isUnlocked: (s) => s.onboardingCompleted,
  },
  {
    id: "onboarding_completed",
    title: "Completed Onboarding",
    description: "Finished the TradeTraxs onboarding flow.",
    icon: "✅",
    isUnlocked: (s) => s.onboardingCompleted,
  },
  {
    id: "likes_100",
    title: "100 Likes Received",
    description: "The community has liked your content 100 times.",
    icon: "❤️",
    isUnlocked: (s) => s.likesReceivedCount >= 100,
  },
  {
    id: "first_public_trade",
    title: "First Public Trade",
    description: "Shared your first public trade with the community.",
    icon: "🌍",
    isUnlocked: (s) => s.publicTradeCount >= 1,
  },
  {
    id: "first_reel",
    title: "First Clip",
    description: "Published your first trading clip.",
    icon: "🎬",
    isUnlocked: (s) => s.reelCount >= 1,
  },
  {
    id: "first_comment",
    title: "First Comment",
    description: "Joined the conversation with your first comment.",
    icon: "💬",
    isUnlocked: (s) => s.commentCount >= 1,
  },
]

function stickyStorageKey(userId: string): string {
  return `${STICKY_STORAGE_KEY}:${userId}`
}

export function readStickyMilestoneUnlocks(userId: string): Set<SystemMilestoneId> {
  if (typeof window === "undefined") return new Set()
  try {
    const raw = window.localStorage.getItem(stickyStorageKey(userId))
    if (!raw) return new Set()
    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) return new Set()
    return new Set(parsed.filter((id) => typeof id === "string"))
  } catch {
    return new Set()
  }
}

export function writeStickyMilestoneUnlocks(
  userId: string,
  unlocked: Set<SystemMilestoneId>
) {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(
      stickyStorageKey(userId),
      JSON.stringify([...unlocked])
    )
  } catch {
    /* ignore quota */
  }
}

export type ResolvedSystemMilestone = SystemMilestone & {
  unlocked: boolean
}

export function resolveSystemMilestones(
  userId: string | null | undefined,
  signals: MilestoneSignals
): ResolvedSystemMilestone[] {
  const sticky = userId ? readStickyMilestoneUnlocks(userId) : new Set<SystemMilestoneId>()
  const nextSticky = new Set(sticky)

  const resolved = SYSTEM_MILESTONES.map((milestone) => {
    const unlockedNow = milestone.isUnlocked(signals)
    if (unlockedNow) nextSticky.add(milestone.id)
    return {
      ...milestone,
      unlocked: unlockedNow || sticky.has(milestone.id),
    }
  })

  if (userId) {
    let changed = nextSticky.size !== sticky.size
    if (!changed) {
      for (const id of nextSticky) {
        if (!sticky.has(id)) {
          changed = true
          break
        }
      }
    }
    if (changed) writeStickyMilestoneUnlocks(userId, nextSticky)
  }

  return resolved
}

export function unlockedSystemMilestones(
  userId: string | null | undefined,
  signals: MilestoneSignals
): ResolvedSystemMilestone[] {
  return resolveSystemMilestones(userId, signals).filter((m) => m.unlocked)
}
