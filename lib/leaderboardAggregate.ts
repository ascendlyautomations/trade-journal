import {
  buildLeaderboardRankings,
  type LeaderboardAccountTypeFilter,
  type LeaderboardChartRow,
  type LeaderboardCustomRange,
  type LeaderboardRankedTrader,
  type LeaderboardTodayStats,
  type LeaderboardView,
  type LeaderboardYourRank,
  type TradeForLeaderboard,
} from "./leaderboardChart.ts"
import { buildLeaderboardChartDataWithFallback } from "./leaderboardTimeframeFallback.ts"

export const LEADERBOARD_RANK_LIMIT = 25

export type LeaderboardProfileFields = {
  id: string
  username: string | null
  name: string | null
  avatar_url: string | null
}

/** Ranked window returned to the browser. No raw trades. */
export type LeaderboardPayload = {
  chartData: LeaderboardChartRow[]
  todayStats: LeaderboardTodayStats
  rankedTraders: LeaderboardRankedTrader[]
  yourRank: LeaderboardYourRank | null
  hasData: boolean
  requestedView: LeaderboardView
  effectiveView: LeaderboardView
  usedFallback: boolean
  profiles: Record<string, LeaderboardProfileFields>
}

export type LeaderboardQuery = {
  view: LeaderboardView
  accountType: LeaderboardAccountTypeFilter
  nowIso: string
  customStartYmd?: string
  customEndYmd?: string
  /** Browser-local custom bounds. Server must not recompute these in UTC. */
  customStartIso?: string
  customEndIso?: string
  viewerId?: string | null
}

const VIEWS = new Set<LeaderboardView>(["7D", "30D", "90D", "YTD", "ALL", "Custom"])
const ACCOUNTS = new Set<LeaderboardAccountTypeFilter>(["all", "funded", "eval", "live"])

export function parseLeaderboardView(value: string | null | undefined): LeaderboardView {
  if (value && VIEWS.has(value as LeaderboardView)) return value as LeaderboardView
  return "7D"
}

export function parseLeaderboardAccount(
  value: string | null | undefined
): LeaderboardAccountTypeFilter {
  if (value && ACCOUNTS.has(value as LeaderboardAccountTypeFilter)) {
    return value as LeaderboardAccountTypeFilter
  }
  return "all"
}

/** Same custom bounds the browser used when filtering locally. */
export function leaderboardCustomInstants(
  startYmd: string,
  endYmd: string
): { startIso: string; endIso: string } | null {
  const startDate = startYmd.trim()
  const endDate = endYmd.trim()
  if (!startDate || !endDate || startDate > endDate) return null
  const startMs = new Date(`${startDate}T00:00:00`).getTime()
  const endMs = new Date(`${endDate}T23:59:59.999`).getTime()
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs)) return null
  return {
    startIso: new Date(startMs).toISOString(),
    endIso: new Date(endMs).toISOString(),
  }
}

/** Minute bucket so a 60s server cache is shared without mixing timeframes. */
export function leaderboardCacheNowBucket(nowIso: string): string {
  const ms = new Date(nowIso).getTime()
  if (!Number.isFinite(ms)) return "0"
  return String(Math.floor(ms / 60_000))
}

export function leaderboardAggregateCacheKey(query: LeaderboardQuery): string {
  const custom =
    query.customStartIso && query.customEndIso
      ? { startIso: query.customStartIso, endIso: query.customEndIso }
      : leaderboardCustomInstants(query.customStartYmd ?? "", query.customEndYmd ?? "")
  return [
    query.view,
    query.accountType,
    leaderboardCacheNowBucket(query.nowIso),
    custom?.startIso ?? "",
    custom?.endIso ?? "",
    query.customStartYmd ?? "",
    query.customEndYmd ?? "",
    query.viewerId ?? "",
  ].join("|")
}

/**
 * Explicit tie-break matching the previous stable sort.
 * Trades must be ordered by created_at, then user_id, which is how the
 * leaderboard scan returned them. Equal P&L keeps the trader whose first
 * trade in that ordered list appears first, then user id.
 */
export function rankLeaderboardTraders(
  trades: TradeForLeaderboard[],
  limit = LEADERBOARD_RANK_LIMIT
): LeaderboardRankedTrader[] {
  const ordered = [...trades].sort((a, b) => {
    const at = new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    if (at !== 0) return at
    return String(a.user_id).localeCompare(String(b.user_id))
  })
  return buildLeaderboardRankings(ordered, limit)
}

/** Same numbers as the old client pipeline, without sending the trade rows. */
export function buildLeaderboardPayloadFromTrades(
  trades: TradeForLeaderboard[],
  query: LeaderboardQuery
): LeaderboardPayload {
  const customRange: LeaderboardCustomRange | undefined =
    query.view === "Custom"
      ? {
          startDate: query.customStartYmd ?? "",
          endDate: query.customEndYmd ?? "",
        }
      : undefined
  const built = buildLeaderboardChartDataWithFallback(
    trades,
    query.view,
    query.viewerId ?? null,
    customRange,
    query.accountType
  )
  return {
    chartData: built.chartData,
    todayStats: built.todayStats,
    rankedTraders: built.rankedTraders,
    yourRank: built.yourRank,
    hasData: built.hasData,
    requestedView: built.requestedView,
    effectiveView: built.effectiveView,
    usedFallback: built.usedFallback,
    profiles: {},
  }
}

function num(value: unknown): number {
  const n = Number(value)
  return Number.isFinite(n) ? n : 0
}

function nullableNum(value: unknown): number | null {
  if (value === null || value === undefined) return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

export function normalizeLeaderboardPayload(raw: unknown): LeaderboardPayload | null {
  if (!raw || typeof raw !== "object") return null
  const row = raw as Record<string, unknown>
  const requestedView = parseLeaderboardView(String(row.requestedView ?? "7D"))
  const effectiveView = parseLeaderboardView(String(row.effectiveView ?? requestedView))
  const rankedRaw = Array.isArray(row.rankedTraders) ? row.rankedTraders : []
  const chartRaw = Array.isArray(row.chartData) ? row.chartData : []
  const stats = (row.todayStats ?? {}) as Record<string, unknown>
  const your = row.yourRank as Record<string, unknown> | null
  const profilesRaw = (row.profiles ?? {}) as Record<string, LeaderboardProfileFields>

  const rankedTraders: LeaderboardRankedTrader[] = rankedRaw.slice(0, LEADERBOARD_RANK_LIMIT).map(
    (item, index) => {
      const trader = item as Record<string, unknown>
      return {
        rank: num(trader.rank) || index + 1,
        userId: String(trader.userId ?? ""),
        totalPnl: num(trader.totalPnl),
        tradeCount: num(trader.tradeCount),
        avgRR: nullableNum(trader.avgRR),
      }
    }
  )

  const chartData: LeaderboardChartRow[] = chartRaw.map((item) => {
    const bucket = item as Record<string, unknown>
    return {
      bucketId: String(bucket.bucketId ?? ""),
      label: String(bucket.label ?? ""),
      sortKey: num(bucket.sortKey),
      average: num(bucket.average),
      best: num(bucket.best),
      worst: num(bucket.worst),
      you: num(bucket.you),
      contributorCount: num(bucket.contributorCount),
    }
  })

  const profiles: Record<string, LeaderboardProfileFields> = {}
  for (const [id, profile] of Object.entries(profilesRaw)) {
    if (!profile || typeof profile !== "object") continue
    profiles[id] = {
      id: String(profile.id ?? id),
      username: profile.username ?? null,
      name: profile.name ?? null,
      avatar_url: profile.avatar_url ?? null,
    }
  }

  const yourRank: LeaderboardYourRank | null =
    your && typeof your === "object"
      ? {
          rank: num(your.rank),
          totalTraders: num(your.totalTraders),
          percentileTopPct: String(your.percentileTopPct ?? "0.0"),
          totalPnl: num(your.totalPnl),
          tradeCount: num(your.tradeCount),
        }
      : null

  return {
    chartData,
    todayStats: {
      yourTradeCount: num(stats.yourTradeCount),
      yourAvgPnl: num(stats.yourAvgPnl),
      yourAvgRR: nullableNum(stats.yourAvgRR),
      globalAvgPnl: num(stats.globalAvgPnl),
      globalAvgRR: nullableNum(stats.globalAvgRR),
      globalTradeCount: num(stats.globalTradeCount),
      percentileTopPct: String(stats.percentileTopPct ?? "0.0"),
    },
    rankedTraders,
    yourRank,
    hasData: row.hasData === true,
    requestedView,
    effectiveView,
    usedFallback: row.usedFallback === true,
    profiles,
  }
}
