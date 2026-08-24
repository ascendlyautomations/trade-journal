import { formatRelativeTime } from "@/lib/formatRelativeTime"
import type { DashboardSessionBucket } from "@/lib/dashboardSessionBuckets"
import { normalizeSessionBucket } from "@/lib/dashboardSessionBuckets"
import { supabase } from "@/lib/supabaseClient"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { normalizeTraderType } from "@/lib/traderType"

export type ExploreProfile = {
  id: string
  username: string | null
  name: string | null
  avatar_url: string | null
  bio: string | null
  is_private?: boolean | null
  created_at: string
  trader_type?: string | null
  trading_style?: string | null
  trading_model?: string | null
  primary_market?: string | null
  started_trading?: string | null
  followers_count?: number
  following_count?: number
}

export type TraderTradeMeta = {
  dominantSession: DashboardSessionBucket | null
  topSymbols: string[]
}

export type ExploreSocialCounts = {
  followers: Record<string, number>
  following: Record<string, number>
}

export type UserTradeSummary = {
  tradeCount: number
  winCount: number
  totalPnl: number
  lastTradeAt: string | null
}

export type UserPostSummary = {
  postCount: number
  lastPostAt: string | null
}

const DAY_MS = 24 * 60 * 60 * 1000

export const EXPLORE_TOP_LIMIT = 8
export const EXPLORE_ACTIVE_LIMIT = 12
export const EXPLORE_NEW_LIMIT = 12
export const EXPLORE_PAGE_SIZE = 16
export const EXPLORE_PROFILE_POOL_LIMIT = EXPLORE_PAGE_SIZE
export const EXPLORE_MIN_SECTION_SIZE = 2
/** Cap rows pulled for Explore ranking — full leaderboard lives on /leaderboard. */
export const EXPLORE_TRADE_ROW_LIMIT = 3000

export type ExploreTopView = "30D" | "90D" | "YTD" | "ALL"

export function getExploreTradeWindowCutoff(
  view: ExploreTopView,
  now = Date.now()
): string | null {
  if (view === "ALL") return null
  if (view === "YTD") {
    return new Date(new Date(now).getFullYear(), 0, 1).toISOString()
  }
  const days = view === "30D" ? 30 : 90
  return new Date(now - days * DAY_MS).toISOString()
}

export function mergeExploreProfiles(
  ...groups: (ExploreProfile[] | null | undefined)[]
): ExploreProfile[] {
  const map = new Map<string, ExploreProfile>()
  for (const group of groups) {
    for (const profile of group ?? []) {
      if (profile?.id) map.set(profile.id, profile)
    }
  }
  return Array.from(map.values())
}

function isRecent(iso: string, days: number, now = Date.now()): boolean {
  const ms = new Date(iso).getTime()
  if (!Number.isFinite(ms)) return false
  return now - ms <= days * DAY_MS
}

function hasAvatar(avatarUrl: string | null | undefined): boolean {
  const raw = avatarUrl?.trim() ?? ""
  return raw.length > 0
}

/** Lightweight activity score for Discover — no ML, existing profile/trade/post signals only. */
export function scoreActiveTrader(
  profile: ExploreProfile,
  trades: UserTradeSummary | undefined,
  posts: UserPostSummary | undefined,
  now = Date.now()
): number {
  let score = 0

  if (profile.username?.trim()) score += 1
  if (hasAvatar(profile.avatar_url)) score += 2
  if (profile.bio?.trim()) score += 2
  if (profile.is_private !== true) score += 1
  if (profile.trader_type?.trim()) score += 1
  if (profile.trading_style?.trim() || profile.trading_model?.trim()) score += 1
  if (profile.primary_market?.trim()) score += 1
  if (profile.started_trading) score += 1

  if (trades && trades.tradeCount > 0) score += 3
  if (trades?.lastTradeAt && isRecent(trades.lastTradeAt, 30, now)) score += 4

  if (posts && posts.postCount > 0) score += 1
  if (posts?.lastPostAt && isRecent(posts.lastPostAt, 30, now)) score += 1

  return score
}

export function buildTradeSummaries(
  trades: {
    user_id: string
    pnl?: number | string | null
    created_at?: string | null
  }[]
): Record<string, UserTradeSummary> {
  const map: Record<string, UserTradeSummary> = {}

  for (const trade of trades) {
    const userId = trade.user_id
    if (!userId) continue

    if (!map[userId]) {
      map[userId] = {
        tradeCount: 0,
        winCount: 0,
        totalPnl: 0,
        lastTradeAt: null,
      }
    }

    const row = map[userId]
    const pnl = Number(trade.pnl)
    row.tradeCount += 1
    if (Number.isFinite(pnl) && pnl > 0) row.winCount += 1
    if (Number.isFinite(pnl)) row.totalPnl += pnl

    if (
      trade.created_at &&
      (!row.lastTradeAt ||
        new Date(trade.created_at).getTime() > new Date(row.lastTradeAt).getTime())
    ) {
      row.lastTradeAt = trade.created_at
    }
  }

  return map
}

export function buildPostSummaries(
  posts: { user_id: string; created_at: string }[]
): Record<string, UserPostSummary> {
  const map: Record<string, UserPostSummary> = {}

  for (const post of posts) {
    const userId = post.user_id
    if (!userId) continue

    if (!map[userId]) {
      map[userId] = { postCount: 0, lastPostAt: null }
    }

    map[userId].postCount += 1
    if (
      !map[userId].lastPostAt ||
      new Date(post.created_at).getTime() >
        new Date(map[userId].lastPostAt!).getTime()
    ) {
      map[userId].lastPostAt = post.created_at
    }
  }

  return map
}

export function rankActiveTraders(
  profiles: ExploreProfile[],
  tradeSummaries: Record<string, UserTradeSummary>,
  postSummaries: Record<string, UserPostSummary>,
  options: {
    excludeUserIds?: Set<string>
    limit?: number
    minScore?: number
  } = {}
): ExploreProfile[] {
  const { excludeUserIds = new Set(), limit = 12, minScore = 3 } = options
  const now = Date.now()

  return profiles
    .filter(
      (p) =>
        p.username?.trim() &&
        !excludeUserIds.has(p.id) &&
        p.is_private !== true
    )
    .map((profile) => ({
      profile,
      score: scoreActiveTrader(
        profile,
        tradeSummaries[profile.id],
        postSummaries[profile.id],
        now
      ),
      lastActivityMs: Math.max(
        tradeSummaries[profile.id]?.lastTradeAt
          ? new Date(tradeSummaries[profile.id]!.lastTradeAt!).getTime()
          : 0,
        postSummaries[profile.id]?.lastPostAt
          ? new Date(postSummaries[profile.id]!.lastPostAt!).getTime()
          : 0,
        new Date(profile.created_at).getTime()
      ),
    }))
    .filter((row) => row.score >= minScore)
    .sort((a, b) => b.score - a.score || b.lastActivityMs - a.lastActivityMs)
    .slice(0, limit)
    .map((row) => row.profile)
}

export function formatJoinedLabel(createdAt: string): string {
  const relative = formatRelativeTime(createdAt)
  if (!relative) return "Joined recently"
  if (relative === "Just now") return "Joined just now"
  return `Joined ${relative.charAt(0).toLowerCase()}${relative.slice(1)}`
}

export function bioPreview(bio: string | null | undefined, maxLen = 96): string {
  const text = bio?.trim() ?? ""
  if (!text) return "No bio yet"
  if (text.length <= maxLen) return text
  return `${text.slice(0, maxLen).trim()}…`
}

/** Years + months trading label (matches public profile display). */
export function formatTradingExperience(
  startedTrading: string | null | undefined
): string | null {
  if (!startedTrading) return null
  const start = new Date(startedTrading)
  if (Number.isNaN(start.getTime())) return null

  const now = new Date()
  const months =
    (now.getFullYear() - start.getFullYear()) * 12 +
    (now.getMonth() - start.getMonth())
  const years = Math.floor(months / 12)
  const remainingMonths = months % 12

  if (years <= 0 && remainingMonths <= 0) return "< 1 mo"
  if (years <= 0) return `${remainingMonths} mo`
  if (remainingMonths === 0) return `${years} yr`
  return `${years}y ${remainingMonths}m`
}

export function enrichExploreProfilesWithSocialCounts(
  profiles: ExploreProfile[],
  counts: ExploreSocialCounts
): ExploreProfile[] {
  return profiles.map((profile) => ({
    ...profile,
    followers_count: counts.followers[profile.id] ?? profile.followers_count ?? 0,
    following_count: counts.following[profile.id] ?? profile.following_count ?? 0,
  }))
}

function isMissingExploreRpc(error: {
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

export async function fetchExploreSocialCounts(
  profileIds: string[]
): Promise<ExploreSocialCounts> {
  const followers: Record<string, number> = {}
  const following: Record<string, number> = {}

  if (!profileIds.length || isDemoModeActive()) {
    return { followers, following }
  }

  const unique = [...new Set(profileIds)]
  const { data, error } = await supabase.rpc("explore_social_counts", {
    p_profile_ids: unique,
  })

  if (!error) {
    for (const row of (data ?? []) as Array<{
      profile_id: string
      followers_count: number | string
      following_count: number | string
    }>) {
      const id = String(row.profile_id)
      followers[id] = Number(row.followers_count) || 0
      following[id] = Number(row.following_count) || 0
    }
    return { followers, following }
  }

  if (!isMissingExploreRpc(error)) {
    console.error("[explore] social counts RPC:", error)
    return { followers, following }
  }

  // Deployment-safe fallback until explore_social_counts is available.
  const [followersRes, followingRes] = await Promise.all([
    supabase.from("followers").select("following_id").in("following_id", unique),
    supabase.from("followers").select("follower_id").in("follower_id", unique),
  ])

  for (const row of followersRes.data ?? []) {
    const id = String(row.following_id)
    followers[id] = (followers[id] ?? 0) + 1
  }

  for (const row of followingRes.data ?? []) {
    const id = String(row.follower_id)
    following[id] = (following[id] ?? 0) + 1
  }

  return { followers, following }
}

export type ExploreTradeMetaPayload = {
  tradeSummaries: Record<string, UserTradeSummary>
  tradeMetaByUserId: Record<string, TraderTradeMeta>
}

type ExploreTradeMetaAggregateRow = {
  row_kind: string
  user_id: string
  trade_count: number | string | null
  win_count: number | string | null
  total_pnl: number | string | null
  last_trade_at: string | null
  session: string | null
  ticker: string | null
  freq: number | string | null
}

/**
 * Explore trade meta from the same recent-public window as the prior client
 * pull (EXPLORE_TRADE_ROW_LIMIT), returned as aggregates instead of raw rows.
 */
export async function fetchExploreTradeMetaAggregates(
  limit = EXPLORE_TRADE_ROW_LIMIT
): Promise<ExploreTradeMetaPayload> {
  const empty: ExploreTradeMetaPayload = {
    tradeSummaries: {},
    tradeMetaByUserId: {},
  }

  if (isDemoModeActive()) {
    const { getDemoExploreTradeMetaRows } = await import("./demo/demoExplore")
    const rows = getDemoExploreTradeMetaRows()
    return {
      tradeSummaries: buildTradeSummaries(rows),
      tradeMetaByUserId: buildTraderTradeMeta(rows),
    }
  }

  const { data, error } = await supabase.rpc("explore_trade_meta_aggregates", {
    p_limit: limit,
  })

  if (error) {
    if (!isMissingExploreRpc(error)) {
      console.error("[explore] trade meta aggregates RPC:", error)
      return empty
    }

    // Deployment-safe fallback: same 3000-row window, client-side aggregate.
    const { data: rows, error: rowsError } = await supabase
      .from("trades")
      .select("user_id, session, ticker, created_at, pnl")
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(limit)

    if (rowsError) {
      console.error("[explore] trade meta fetch error:", rowsError)
      return empty
    }

    const list = (rows || []).filter(
      (
        row
      ): row is {
        user_id: string
        session: string | null
        ticker: string | null
        created_at: string
        pnl: number | null
      } => row.user_id != null && row.created_at != null
    )
    return {
      tradeSummaries: buildTradeSummaries(list),
      tradeMetaByUserId: buildTraderTradeMeta(list),
    }
  }

  const tradeSummaries: Record<string, UserTradeSummary> = {}
  const sessionCounts: Record<string, Record<string, number>> = {}
  const symbolCounts: Record<string, Record<string, number>> = {}

  for (const row of (data ?? []) as ExploreTradeMetaAggregateRow[]) {
    const userId = String(row.user_id)
    if (!userId) continue

    if (row.row_kind === "summary") {
      tradeSummaries[userId] = {
        tradeCount: Number(row.trade_count) || 0,
        winCount: Number(row.win_count) || 0,
        totalPnl: Number(row.total_pnl) || 0,
        lastTradeAt: row.last_trade_at ?? null,
      }
      continue
    }

    if (row.row_kind === "session") {
      const session = normalizeSessionBucket(row.session)
      if (!session) continue
      if (!sessionCounts[userId]) sessionCounts[userId] = {}
      sessionCounts[userId][session] =
        (sessionCounts[userId][session] ?? 0) + (Number(row.freq) || 0)
      continue
    }

    if (row.row_kind === "ticker") {
      const ticker = String(row.ticker ?? "").trim().toUpperCase()
      if (!ticker) continue
      if (!symbolCounts[userId]) symbolCounts[userId] = {}
      symbolCounts[userId][ticker] =
        (symbolCounts[userId][ticker] ?? 0) + (Number(row.freq) || 0)
    }
  }

  const tradeMetaByUserId: Record<string, TraderTradeMeta> = {}
  for (const userId of new Set([
    ...Object.keys(sessionCounts),
    ...Object.keys(symbolCounts),
  ])) {
    const sessions = sessionCounts[userId] ?? {}
    const dominantSession = (
      Object.entries(sessions).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null
    ) as DashboardSessionBucket | null

    const symbols = Object.entries(symbolCounts[userId] ?? {})
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([symbol]) => symbol)

    tradeMetaByUserId[userId] = { dominantSession, topSymbols: symbols }
  }

  return { tradeSummaries, tradeMetaByUserId }
}

export function buildTraderTradeMeta(
  trades: {
    user_id: string | null
    session?: string | null
    ticker?: string | null
  }[]
): Record<string, TraderTradeMeta> {
  const sessionCounts: Record<string, Record<string, number>> = {}
  const symbolCounts: Record<string, Record<string, number>> = {}

  for (const trade of trades) {
    const userId = trade.user_id
    if (!userId) continue

    const session = normalizeSessionBucket(trade.session)
    if (session) {
      if (!sessionCounts[userId]) sessionCounts[userId] = {}
      sessionCounts[userId][session] = (sessionCounts[userId][session] ?? 0) + 1
    }

    const ticker = String(trade.ticker ?? "").trim().toUpperCase()
    if (ticker) {
      if (!symbolCounts[userId]) symbolCounts[userId] = {}
      symbolCounts[userId][ticker] = (symbolCounts[userId][ticker] ?? 0) + 1
    }
  }

  const result: Record<string, TraderTradeMeta> = {}

  for (const userId of new Set([
    ...Object.keys(sessionCounts),
    ...Object.keys(symbolCounts),
  ])) {
    const sessions = sessionCounts[userId] ?? {}
    const dominantSession = (
      Object.entries(sessions).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null
    ) as DashboardSessionBucket | null

    const symbols = Object.entries(symbolCounts[userId] ?? {})
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([symbol]) => symbol)

    result[userId] = { dominantSession, topSymbols: symbols }
  }

  return result
}

export function rankProfilesByTraderType(
  profiles: ExploreProfile[],
  traderType: "Futures" | "Options" | "Investor",
  tradeSummaries: Record<string, UserTradeSummary>,
  options: { excludeUserIds?: Set<string>; limit?: number } = {}
): ExploreProfile[] {
  const { excludeUserIds = new Set(), limit = 12 } = options

  return profiles
    .filter(
      (profile) =>
        profile.username?.trim() &&
        profile.is_private !== true &&
        !excludeUserIds.has(profile.id) &&
        normalizeTraderType(profile.trader_type) === traderType
    )
    .map((profile) => ({
      profile,
      score: scoreActiveTrader(profile, tradeSummaries[profile.id], undefined),
      lastTradeMs: tradeSummaries[profile.id]?.lastTradeAt
        ? new Date(tradeSummaries[profile.id]!.lastTradeAt!).getTime()
        : 0,
      joinedMs: new Date(profile.created_at).getTime(),
    }))
    .sort(
      (a, b) =>
        b.score - a.score ||
        b.lastTradeMs - a.lastTradeMs ||
        b.joinedMs - a.joinedMs
    )
    .slice(0, limit)
    .map((row) => row.profile)
}

export function rankNewTraders(
  profiles: ExploreProfile[],
  tradeSummaries: Record<string, UserTradeSummary>,
  postSummaries: Record<string, UserPostSummary>,
  options: {
    excludeUserIds?: Set<string>
    limit?: number
  } = {}
): ExploreProfile[] {
  const { excludeUserIds = new Set(), limit = 12 } = options
  const now = Date.now()

  return profiles
    .filter(
      (profile) =>
        profile.username?.trim() &&
        profile.is_private !== true &&
        !excludeUserIds.has(profile.id)
    )
    .map((profile) => ({
      profile,
      joinedMs: new Date(profile.created_at).getTime(),
      score: scoreActiveTrader(
        profile,
        tradeSummaries[profile.id],
        postSummaries[profile.id],
        now
      ),
    }))
    .sort((a, b) => b.joinedMs - a.joinedMs || b.score - a.score)
    .slice(0, limit)
    .map((row) => row.profile)
}

/** Single discover list — activity-ranked, no section splits. */
export function rankExploreDiscoverList(
  profiles: ExploreProfile[],
  tradeSummaries: Record<string, UserTradeSummary>,
  postSummaries: Record<string, UserPostSummary>,
  options: { excludeUserIds?: Set<string> } = {}
): ExploreProfile[] {
  const { excludeUserIds = new Set() } = options
  const now = Date.now()

  return profiles
    .filter(
      (profile) =>
        profile.username?.trim() &&
        profile.is_private !== true &&
        !excludeUserIds.has(profile.id)
    )
    .map((profile) => ({
      profile,
      score: scoreActiveTrader(
        profile,
        tradeSummaries[profile.id],
        postSummaries[profile.id],
        now
      ),
      lastActivityMs: Math.max(
        tradeSummaries[profile.id]?.lastTradeAt
          ? new Date(tradeSummaries[profile.id]!.lastTradeAt!).getTime()
          : 0,
        postSummaries[profile.id]?.lastPostAt
          ? new Date(postSummaries[profile.id]!.lastPostAt!).getTime()
          : 0,
        new Date(profile.created_at).getTime()
      ),
    }))
    .sort((a, b) => b.score - a.score || b.lastActivityMs - a.lastActivityMs)
    .map((row) => row.profile)
}
