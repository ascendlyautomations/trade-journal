export type ExploreProfile = {
  id: string
  username: string | null
  name: string | null
  avatar_url: string | null
  bio: string | null
  is_private?: boolean | null
  created_at: string
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

export const EXPLORE_TOP_LIMIT = 6
export const EXPLORE_ACTIVE_LIMIT = 8
export const EXPLORE_NEW_LIMIT = 8
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
  return raw.length > 0 && !raw.includes("default-avatar")
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

  if (trades && trades.tradeCount > 0) score += 3
  if (trades?.lastTradeAt && isRecent(trades.lastTradeAt, 30, now)) score += 4

  if (posts && posts.postCount > 0) score += 1
  if (posts?.lastPostAt && isRecent(posts.lastPostAt, 30, now)) score += 1

  return score
}

export function buildTradeSummaries(
  trades: { user_id: string; pnl?: number | string | null; created_at: string }[]
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
      !row.lastTradeAt ||
      new Date(trade.created_at).getTime() > new Date(row.lastTradeAt).getTime()
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
  const createdMs = new Date(createdAt).getTime()
  if (!Number.isFinite(createdMs)) return "Joined recently"

  const days = Math.floor((Date.now() - createdMs) / DAY_MS)
  if (days <= 0) return "Joined today"
  if (days === 1) return "Joined yesterday"
  if (days < 14) return `Joined ${days} days ago`
  if (days < 60) return "Joined recently"

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    year: "numeric",
  }).format(new Date(createdAt))
}

export function bioPreview(bio: string | null | undefined, maxLen = 96): string {
  const text = bio?.trim() ?? ""
  if (!text) return "No bio yet"
  if (text.length <= maxLen) return text
  return `${text.slice(0, maxLen).trim()}…`
}
