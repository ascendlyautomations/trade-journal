import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "./demo/constants"
import { ensureFullTradesHistory, getTradesSnapshot } from "./appDataCache"
import type { MilestoneSignals } from "./userMilestones"
import {
  buildStreakStats,
  collectJournalWeekdayKeys,
  collectPostingWeekdayKeys,
  computeWeekdayActivityStreak,
  computeWinningTradeStreak,
  JOURNAL_STREAK_MILESTONES,
  POSTING_STREAK_MILESTONES,
  type StreakStats,
  WINNING_STREAK_MILESTONES,
} from "./userStreaksLogic"

export type UserStreaksSnapshot = {
  journal: StreakStats
  posting: StreakStats
  winning: StreakStats
  milestoneSignals: MilestoneSignals
  computedAt: number
}

type CacheEntry = {
  userId: string
  data: UserStreaksSnapshot
  invalidated: boolean
  loading: boolean
}

const EMPTY_MILESTONE_SIGNALS: MilestoneSignals = {
  onboardingCompleted: false,
  tradeCount: 0,
  publicTradeCount: 0,
  profilePostCount: 0,
  reelCount: 0,
  commentCount: 0,
  likesReceivedCount: 0,
}

const EMPTY_STREAK: StreakStats = {
  current: 0,
  longest: 0,
  nextMilestone: JOURNAL_STREAK_MILESTONES[0],
  progressRatio: 0,
  unitLabel: "Days",
}

const EMPTY_SNAPSHOT: UserStreaksSnapshot = {
  journal: { ...EMPTY_STREAK, nextMilestone: JOURNAL_STREAK_MILESTONES[0] },
  posting: {
    ...EMPTY_STREAK,
    nextMilestone: POSTING_STREAK_MILESTONES[0],
  },
  winning: {
    ...EMPTY_STREAK,
    unitLabel: "Wins",
    nextMilestone: WINNING_STREAK_MILESTONES[0],
  },
  milestoneSignals: EMPTY_MILESTONE_SIGNALS,
  computedAt: 0,
}

const streaksByUser = new Map<string, CacheEntry>()
const listeners = new Set<() => void>()

function notify() {
  for (const listener of listeners) {
    listener()
  }
}

export function subscribeUserStreaksCache(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function invalidateUserStreaksCache(userId: string) {
  const entry = streaksByUser.get(userId)
  if (!entry || entry.invalidated) return
  streaksByUser.set(userId, { ...entry, invalidated: true })
  notify()
}

export function clearAllUserStreaksCaches() {
  streaksByUser.clear()
  notify()
}

export function getUserStreaksSnapshot(
  userId: string | null | undefined
): UserStreaksSnapshot | null {
  if (!userId) return null
  const entry = streaksByUser.get(userId)
  if (!entry || entry.invalidated || entry.loading) return null
  return entry.data
}

export function isUserStreaksLoading(userId: string | null | undefined): boolean {
  if (!userId) return false
  if (getUserStreaksSnapshot(userId)) return false
  return streaksByUser.get(userId)?.loading === true
}

function isMissingStreakRpc(error: {
  code?: string
  message?: string
}): boolean {
  const message = String(error.message ?? "").toLowerCase()
  return (
    error.code === "PGRST202" ||
    error.code === "42883" ||
    message.includes("could not find the function") ||
    message.includes("schema cache")
  )
}

type StreakBundleRow = {
  onboarding_completed: boolean
  trade_count: number | string
  public_trade_count: number | string
  profile_post_count: number | string
  reel_count: number | string
  comment_count: number | string
  likes_received_count: number | string
  posting_timestamps: string[] | null
}

/** Legacy path: ID dumps + .in() head counts (pre-RPC). */
async function fetchMilestoneSignalsLegacy(
  supabase: SupabaseClient,
  userId: string,
  trades: readonly any[],
  hints?: { onboardingCompleted?: boolean | null }
): Promise<MilestoneSignals> {
  const tradeIds = trades.map((t) => String(t.id))
  const hasOnboardingHint = typeof hints?.onboardingCompleted === "boolean"

  const profilePromise = hasOnboardingHint
    ? Promise.resolve({
        data: { onboarding_completed: hints!.onboardingCompleted },
        error: null,
      })
    : supabase
        .from("profiles")
        .select("onboarding_completed")
        .eq("id", userId)
        .maybeSingle()

  const [
    profileRes,
    postsCountRes,
    reelsListRes,
    commentsRes,
    feedPostsRes,
    profilePostsListRes,
    tradeLikesRes,
  ] = await Promise.all([
    profilePromise,
    supabase
      .from("profile_posts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId),
    supabase.from("reels").select("id").eq("user_id", userId),
    supabase
      .from("comments")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId),
    supabase.from("posts").select("id").eq("user_id", userId),
    supabase.from("profile_posts").select("id").eq("user_id", userId),
    tradeIds.length
      ? supabase
          .from("trade_likes")
          .select("id", { count: "exact", head: true })
          .in("trade_id", tradeIds)
      : Promise.resolve({ count: 0, data: null, error: null }),
  ])

  const feedPostIds = (feedPostsRes.data ?? []).map((row) => String(row.id))
  const profilePostIds = (profilePostsListRes.data ?? []).map((row) =>
    String(row.id)
  )
  const reelIds = (reelsListRes.data ?? []).map((row) => String(row.id))

  const [feedLikesRes, profilePostLikesRes, reelLikesRes] = await Promise.all([
    feedPostIds.length
      ? supabase
          .from("likes")
          .select("id", { count: "exact", head: true })
          .in("post_id", feedPostIds)
      : Promise.resolve({ count: 0, data: null, error: null }),
    profilePostIds.length
      ? supabase
          .from("profile_post_likes")
          .select("id", { count: "exact", head: true })
          .in("profile_post_id", profilePostIds)
      : Promise.resolve({ count: 0, data: null, error: null }),
    reelIds.length
      ? supabase
          .from("reel_likes")
          .select("id", { count: "exact", head: true })
          .in("reel_id", reelIds)
      : Promise.resolve({ count: 0, data: null, error: null }),
  ])

  const tradeCount = trades.length
  const publicTradeCount = trades.filter((t) => t.is_public === true).length

  const likesReceivedCount =
    (tradeLikesRes.count ?? 0) +
    (feedLikesRes.count ?? 0) +
    (profilePostLikesRes.count ?? 0) +
    (reelLikesRes.count ?? 0)

  return {
    onboardingCompleted: profileRes.data?.onboarding_completed === true,
    tradeCount,
    publicTradeCount,
    profilePostCount: postsCountRes.count ?? 0,
    reelCount: reelIds.length,
    commentCount: commentsRes.count ?? 0,
    likesReceivedCount,
  }
}

async function fetchPostingTimestampsLegacy(
  supabase: SupabaseClient,
  userId: string,
  trades: readonly any[]
): Promise<string[]> {
  const publicTradeTimes = trades
    .filter((t) => t.is_public === true)
    .map((t) => String(t.created_at ?? ""))

  const [postsRes, reelsRes] = await Promise.all([
    supabase.from("profile_posts").select("created_at").eq("user_id", userId),
    supabase.from("reels").select("created_at").eq("user_id", userId),
  ])

  const postTimes = (postsRes.data ?? []).map((row) =>
    String(row.created_at ?? "")
  )
  const reelTimes = (reelsRes.data ?? []).map((row) =>
    String(row.created_at ?? "")
  )

  return [...publicTradeTimes, ...postTimes, ...reelTimes]
}

/**
 * Milestone signals + posting timestamps in one aggregate RPC.
 * tradeCount / publicTradeCount stay derived from the full trades cache so
 * journal/winning streaks and milestone trade counts share one source of truth.
 */
async function fetchStreakMilestoneBundle(
  supabase: SupabaseClient,
  userId: string,
  trades: readonly any[],
  hints?: { onboardingCompleted?: boolean | null }
): Promise<{ signals: MilestoneSignals; postingTimestamps: string[] }> {
  const tradeCount = trades.length
  const publicTradeCount = trades.filter((t) => t.is_public === true).length
  const hasOnboardingHint = typeof hints?.onboardingCompleted === "boolean"

  const { data, error } = await supabase.rpc("user_streak_milestone_bundle", {
    p_user_id: userId,
  })

  if (error) {
    if (isMissingStreakRpc(error)) {
      const [signals, postingTimestamps] = await Promise.all([
        fetchMilestoneSignalsLegacy(supabase, userId, trades, hints),
        fetchPostingTimestampsLegacy(supabase, userId, trades),
      ])
      return { signals, postingTimestamps }
    }
    console.error("[streaks] milestone bundle RPC:", error)
    return {
      signals: {
        ...EMPTY_MILESTONE_SIGNALS,
        onboardingCompleted: hasOnboardingHint
          ? hints!.onboardingCompleted === true
          : false,
        tradeCount,
        publicTradeCount,
      },
      postingTimestamps: trades
        .filter((t) => t.is_public === true)
        .map((t) => String(t.created_at ?? "")),
    }
  }

  const row = (Array.isArray(data) ? data[0] : data) as StreakBundleRow | null
  if (!row) {
    return {
      signals: {
        ...EMPTY_MILESTONE_SIGNALS,
        onboardingCompleted: hasOnboardingHint
          ? hints!.onboardingCompleted === true
          : false,
        tradeCount,
        publicTradeCount,
      },
      postingTimestamps: [],
    }
  }

  const signals: MilestoneSignals = {
    onboardingCompleted: hasOnboardingHint
      ? hints!.onboardingCompleted === true
      : row.onboarding_completed === true,
    tradeCount,
    publicTradeCount,
    profilePostCount: Number(row.profile_post_count) || 0,
    reelCount: Number(row.reel_count) || 0,
    commentCount: Number(row.comment_count) || 0,
    likesReceivedCount: Number(row.likes_received_count) || 0,
  }

  const postingTimestamps = (row.posting_timestamps ?? []).map((ts) =>
    String(ts ?? "")
  )

  return { signals, postingTimestamps }
}

function computeSnapshot(
  trades: readonly any[],
  postingTimestamps: readonly string[],
  milestoneSignals: MilestoneSignals
): UserStreaksSnapshot {
  const journalRun = computeWeekdayActivityStreak(collectJournalWeekdayKeys(trades))
  const postingRun = computeWeekdayActivityStreak(
    collectPostingWeekdayKeys(postingTimestamps)
  )
  const winningRun = computeWinningTradeStreak(trades)

  return {
    journal: buildStreakStats(
      journalRun.current,
      journalRun.longest,
      JOURNAL_STREAK_MILESTONES,
      "Days"
    ),
    posting: buildStreakStats(
      postingRun.current,
      postingRun.longest,
      POSTING_STREAK_MILESTONES,
      "Days"
    ),
    winning: buildStreakStats(
      winningRun.current,
      winningRun.longest,
      WINNING_STREAK_MILESTONES,
      "Wins"
    ),
    milestoneSignals,
    computedAt: Date.now(),
  }
}

export async function ensureUserStreaksLoaded(
  supabase: SupabaseClient,
  userId: string,
  options?: { force?: boolean; onboardingCompleted?: boolean | null }
): Promise<UserStreaksSnapshot> {
  if (!options?.force) {
    const cached = getUserStreaksSnapshot(userId)
    if (cached) return cached
  }

  const existing = streaksByUser.get(userId)
  if (!options?.force && existing?.loading) {
    return existing.data ?? EMPTY_SNAPSHOT
  }

  streaksByUser.set(userId, {
    userId,
    data: existing?.data ?? EMPTY_SNAPSHOT,
    invalidated: false,
    loading: true,
  })
  notify()

  // Streak trade counts must match full journal history (not the 120 warm window).
  await ensureFullTradesHistory(supabase, userId).catch(() => [])
  const trades = [...getTradesSnapshot(userId)]
  const { signals: milestoneSignals, postingTimestamps } =
    await fetchStreakMilestoneBundle(supabase, userId, trades, {
      onboardingCompleted: options?.onboardingCompleted,
    })

  const snapshot = computeSnapshot(trades, postingTimestamps, milestoneSignals)

  streaksByUser.set(userId, {
    userId,
    data: snapshot,
    invalidated: false,
    loading: false,
  })
  notify()

  return snapshot
}

export function primeUserStreaksFromTrades(
  userId: string,
  trades: readonly any[],
  postingTimestamps: readonly string[] = [],
  milestoneSignals?: Partial<MilestoneSignals>
) {
  if (isDemoUserId(userId)) {
    const signals: MilestoneSignals = {
      ...EMPTY_MILESTONE_SIGNALS,
      onboardingCompleted: true,
      tradeCount: trades.length,
      publicTradeCount: trades.filter((t) => t.is_public === true).length,
      ...milestoneSignals,
    }
    const snapshot = computeSnapshot(trades, postingTimestamps, signals)
    streaksByUser.set(userId, {
      userId,
      data: snapshot,
      invalidated: false,
      loading: false,
    })
    notify()
  }
}
