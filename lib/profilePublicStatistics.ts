import { averageRrFromTrades } from "./tradeRr.ts"

export type ProfileSummaryTradeRow = {
  id?: unknown
  created_at?: string | null
  pnl?: unknown
  rr?: unknown
  mode?: string | null
  account_type?: string | null
  direction?: string | null
  session?: string | null
  is_public?: boolean | null
}

export type ProfilePublicStatsAggregate = {
  totalTrades: number
  wins: number
  totalPnl: number
  avgRr: number | null
}

/** RPC `public_stats` envelope (snake_case). */
export type ProfileBootstrapPublicStatsV1 = {
  total_trades: number
  wins: number
  total_pnl: number
}

export function overviewStatsFromBootstrapPublicStats(
  stats: ProfileBootstrapPublicStatsV1
): ProfilePublicStatsAggregate {
  return {
    totalTrades: stats.total_trades,
    wins: stats.wins,
    totalPnl: stats.total_pnl,
    avgRr: null,
  }
}

/** Skip the legacy all-public-trades summary fetch when bootstrap stats are present. */
export function shouldFetchProfileSummaryTrades(input: {
  profileId: string | null | undefined
  canViewTrades: boolean
  summaryReady: boolean
  bootstrapPublicStats: ProfileBootstrapPublicStatsV1 | null
}): boolean {
  if (!input.profileId || !input.canViewTrades || input.summaryReady) return false
  if (input.bootstrapPublicStats != null) return false
  return true
}

function isBacktestTrade(trade: ProfileSummaryTradeRow): boolean {
  const modeValue = String(trade.mode ?? "").trim().toLowerCase()
  const accountType = String(trade.account_type ?? "").trim().toLowerCase()
  return modeValue === "backtest" || accountType === "backtest"
}

/** Overview header stats — excludes backtests (matches useProfileStatistics). */
export function computeProfileOverviewStats(
  trades: readonly ProfileSummaryTradeRow[]
): ProfilePublicStatsAggregate {
  const eligible = trades.filter((t) => !isBacktestTrade(t))
  const totalTrades = eligible.length
  const wins = eligible.filter((t) => Number(t.pnl) > 0).length
  const totalPnl = eligible.reduce(
    (sum, t) => sum + (Number(t.pnl) || 0),
    0
  )
  return {
    totalTrades,
    wins,
    totalPnl,
    avgRr: averageRrFromTrades(eligible),
  }
}

export function computeProfileOverviewWinRate(stats: ProfilePublicStatsAggregate): number {
  if (stats.totalTrades <= 0) return 0
  return (stats.wins / stats.totalTrades) * 100
}

/** Full analytics tab stats input — public trades only, mode filter applied upstream. */
export function computeProfileAnalyticsStats(
  trades: readonly ProfileSummaryTradeRow[],
  selectedMode: string
) {
  const publicTrades = trades.filter((t) => t.is_public === true)
  const filtered = publicTrades.filter((trade) => {
    if (selectedMode === "all") return true
    const mode = selectedMode.toLowerCase()
    const modeValue = String(trade.mode ?? "").trim().toLowerCase()
    const accountType = String(trade.account_type ?? "").trim().toLowerCase()
    return modeValue === mode || accountType === mode
  })
  const analyticsTrades = filtered.filter((t) => !isBacktestTrade(t))
  const totalTrades = analyticsTrades.length
  const wins = analyticsTrades.filter((t) => Number(t.pnl) > 0).length
  const totalPnl = analyticsTrades.reduce(
    (sum, t) => sum + (Number(t.pnl) || 0),
    0
  )
  const grossWins = analyticsTrades.reduce((sum, t) => {
    const pnl = Number(t.pnl) || 0
    return pnl > 0 ? sum + pnl : sum
  }, 0)
  const grossLosses = analyticsTrades.reduce((sum, t) => {
    const pnl = Number(t.pnl) || 0
    return pnl < 0 ? sum + pnl : sum
  }, 0)
  const profitFactor =
    grossLosses < 0 ? grossWins / Math.abs(grossLosses) : null

  return {
    analyticsTrades,
    totalTrades,
    wins,
    totalPnl,
    profitFactor,
    avgRr: averageRrFromTrades(analyticsTrades),
  }
}
