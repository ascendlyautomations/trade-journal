import { analyticsModeEffective } from "./analytics/analyticsModeEffective.ts"
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
  payoutTotal: number | null
  profitFactor: number | null
}

/** RPC `public_stats` envelope (snake_case). */
export type ProfileBootstrapPublicStatsV1 = {
  total_trades: number
  wins: number
  total_pnl: number
  profit_factor?: number | string | null
  average_rr?: number | string | null
  payout_total?: number | string | null
}

function finiteNumber(value: unknown): number | null {
  if (value == null || value === "") return null
  const n = typeof value === "number" ? value : Number(value)
  return Number.isFinite(n) ? n : null
}

export function overviewStatsFromBootstrapPublicStats(
  stats: ProfileBootstrapPublicStatsV1
): ProfilePublicStatsAggregate {
  return {
    totalTrades: Number(stats.total_trades) || 0,
    wins: Number(stats.wins) || 0,
    totalPnl: finiteNumber(stats.total_pnl) ?? 0,
    avgRr: finiteNumber(stats.average_rr),
    payoutTotal:
      stats.payout_total === undefined ? null : finiteNumber(stats.payout_total),
    profitFactor: finiteNumber(stats.profit_factor),
  }
}

/** SQL `profile_statistics_trade_matches_mode` for the profile chips. */
export function profileTradeMatchesStatisticsMode(
  trade: { mode?: unknown; account_type?: unknown },
  selectedMode: string
): boolean {
  const effective = analyticsModeEffective({
    accountType: trade.account_type == null ? null : String(trade.account_type),
    tradeMode: trade.mode == null ? null : String(trade.mode),
  })
  if (selectedMode === "all") return effective !== "backtest"
  if (selectedMode === "eval" || selectedMode === "evaluation") {
    return effective === "evaluation"
  }
  if (selectedMode === "backtest") return effective === "backtest"
  if (selectedMode === "sim") return effective === "sim"
  return effective === selectedMode
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
    payoutTotal: null,
    profitFactor: null,
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
  const analyticsTrades = publicTrades.filter((trade) =>
    profileTradeMatchesStatisticsMode(trade, selectedMode)
  )
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

export type ProfileStatisticsModeView = {
  filteredTradeCount: number
  profitFactor: number | null
  averageWinner: number | null
  averageLoser: number | null
  profitPerTrade: number | null
  biggestWin: number
  biggestLoss: number | null
  longTrades: number
  maxWinStreak: number
  maxLossStreak: number
  sessionTotal: number
  sessionBreakdown: Array<{
    label: "NY" | "London" | "Asia"
    count: number
    pct: number
  }>
  currentEquity: number
  equityData: Array<{ index: number; equity: number }>
}

const EMPTY_PROFILE_STATISTICS_MODE: ProfileStatisticsModeView = {
  filteredTradeCount: 0,
  profitFactor: null,
  averageWinner: null,
  averageLoser: null,
  profitPerTrade: null,
  biggestWin: 0,
  biggestLoss: null,
  longTrades: 0,
  maxWinStreak: 0,
  maxLossStreak: 0,
  sessionTotal: 0,
  sessionBreakdown: [],
  currentEquity: 0,
  equityData: [],
}

/** Adapt one `rpc_v1_profile_statistics_bootstrap` mode object to the Stats tab. */
export function mapProfileStatisticsMode(
  raw: unknown
): ProfileStatisticsModeView {
  if (!raw || typeof raw !== "object") return EMPTY_PROFILE_STATISTICS_MODE
  const row = raw as Record<string, unknown>
  const sessions = Array.isArray(row.session_breakdown)
    ? row.session_breakdown
    : []
  const equity = Array.isArray(row.equity_data) ? row.equity_data : []
  const sessionBreakdown: ProfileStatisticsModeView["sessionBreakdown"] = []
  for (const entry of sessions) {
    if (!entry || typeof entry !== "object") continue
    const item = entry as Record<string, unknown>
    const label = item.label
    if (label !== "NY" && label !== "London" && label !== "Asia") continue
    sessionBreakdown.push({
      label,
      count: finiteNumber(item.count) ?? 0,
      pct: finiteNumber(item.pct) ?? 0,
    })
  }
  return {
    filteredTradeCount: finiteNumber(row.filtered_trade_count) ?? 0,
    profitFactor: finiteNumber(row.profit_factor),
    averageWinner: finiteNumber(row.average_winner),
    averageLoser: finiteNumber(row.average_loser),
    profitPerTrade: finiteNumber(row.profit_per_trade),
    biggestWin: finiteNumber(row.biggest_win) ?? 0,
    biggestLoss: finiteNumber(row.biggest_loss),
    longTrades: finiteNumber(row.long_trades) ?? 0,
    maxWinStreak: finiteNumber(row.max_win_streak) ?? 0,
    maxLossStreak: finiteNumber(row.max_loss_streak) ?? 0,
    sessionTotal: finiteNumber(row.session_total) ?? 0,
    sessionBreakdown,
    currentEquity: finiteNumber(row.current_equity) ?? 0,
    equityData: equity.flatMap((entry) => {
      if (!entry || typeof entry !== "object") return []
      const point = entry as Record<string, unknown>
      const index = finiteNumber(point.index)
      const value = finiteNumber(point.equity)
      if (index == null || value == null) return []
      return [{ index, equity: value }]
    }),
  }
}
