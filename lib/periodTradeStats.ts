import {
  computeHoldTimeStats,
  type HoldTimeStats,
} from "@/lib/dashboardHoldTimeStats"
import {
  computeSideProfitFactor,
  computeTradePnlStreaks,
  normalizeTradeDirection,
} from "@/lib/dashboardLongShortStats"
import { compareDashboardTradesChronological } from "@/lib/dashboardTradeDate"
import { computePerformanceStats } from "@/lib/performanceShare"
import { averageRrFromTrades, hasStoredRr, parseOptionalRr } from "@/lib/tradeRr"

export type PeriodDailyConsistency = {
  tradingDays: number
  greenDays: number
  redDays: number
  breakEvenDays: number
  avgDailyPnl: number | null
  bestDayPnl: number | null
  worstDayPnl: number | null
}

export type PeriodTradeStats = {
  totalTrades: number
  winningTrades: number
  losingTrades: number
  breakEvenTrades: number
  winRate: number | null
  totalPnl: number
  avgTradePnl: number | null
  bestTrade: number | null
  worstTrade: number | null
  profitFactor: number | null
  /** Infinity when there are wins and no losses. */
  profitFactorInfinite: boolean
  avgRR: number | null
  totalRR: number | null
  avgWin: number | null
  avgLoss: number | null
  largestWin: number | null
  largestLoss: number | null
  longTrades: number
  shortTrades: number
  hasDirectionData: boolean
  avgHoldSeconds: number | null
  holdTime: HoldTimeStats
  avgContracts: number | null
  totalContracts: number | null
  hasContractData: boolean
  consistency: PeriodDailyConsistency
  longestWinStreak: number
  longestLossStreak: number
}

function emptyConsistency(): PeriodDailyConsistency {
  return {
    tradingDays: 0,
    greenDays: 0,
    redDays: 0,
    breakEvenDays: 0,
    avgDailyPnl: null,
    bestDayPnl: null,
    worstDayPnl: null,
  }
}

/** Green / red / break-even day counts from per-day P&L totals. */
export function computeDailyConsistency(
  dailyPnls: readonly number[]
): PeriodDailyConsistency {
  if (dailyPnls.length === 0) return emptyConsistency()

  let greenDays = 0
  let redDays = 0
  let breakEvenDays = 0
  let sum = 0
  let best = dailyPnls[0]
  let worst = dailyPnls[0]

  for (const pnl of dailyPnls) {
    const value = Number(pnl) || 0
    sum += value
    if (value > 0) greenDays += 1
    else if (value < 0) redDays += 1
    else breakEvenDays += 1
    if (value > best) best = value
    if (value < worst) worst = value
  }

  return {
    tradingDays: dailyPnls.length,
    greenDays,
    redDays,
    breakEvenDays,
    avgDailyPnl: sum / dailyPnls.length,
    bestDayPnl: best,
    worstDayPnl: worst,
  }
}

/**
 * Period overview stats for Calendar monthly panel / similar summaries.
 * Reuses shared performance, profit-factor, RR, hold-time, and streak helpers.
 */
export function computePeriodTradeStats(
  trades: readonly any[],
  options?: { dailyPnls?: readonly number[] }
): PeriodTradeStats {
  const list = Array.isArray(trades) ? [...trades] : []
  const performance = computePerformanceStats(list)
  const wins = list.filter((t) => (Number(t.pnl) || 0) > 0)
  const losses = list.filter((t) => (Number(t.pnl) || 0) < 0)
  const pnls = list.map((t) => Number(t.pnl) || 0)

  const bestTrade = list.length ? Math.max(...pnls) : null
  const worstTrade = list.length ? Math.min(...pnls) : null
  const largestWin = wins.length
    ? Math.max(...wins.map((t) => Number(t.pnl) || 0))
    : null
  const largestLoss = losses.length
    ? Math.min(...losses.map((t) => Number(t.pnl) || 0))
    : null

  const avgWin =
    wins.length > 0
      ? wins.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0) / wins.length
      : null
  const avgLoss =
    losses.length > 0
      ? losses.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0) / losses.length
      : null

  const hasLosses = losses.length > 0
  const hasWins = wins.length > 0
  const profitFactorInfinite = hasWins && !hasLosses
  const profitFactor =
    list.length === 0
      ? null
      : profitFactorInfinite
        ? null
        : hasLosses
          ? computeSideProfitFactor(list)
          : null

  const rrValues: number[] = []
  for (const trade of list) {
    if (!hasStoredRr(trade?.rr)) continue
    const rr = parseOptionalRr(trade.rr)
    if (rr != null) rrValues.push(rr)
  }
  const totalRR =
    rrValues.length > 0
      ? rrValues.reduce((sum, rr) => sum + rr, 0)
      : null

  let longTrades = 0
  let shortTrades = 0
  let hasDirectionData = false
  for (const trade of list) {
    const side = normalizeTradeDirection(trade?.direction)
    if (!side) continue
    hasDirectionData = true
    if (side === "Long") longTrades += 1
    else shortTrades += 1
  }

  const holdTime = computeHoldTimeStats(list)

  const contractValues = list
    .map((t) => Number(t?.contracts))
    .filter((n) => Number.isFinite(n) && n > 0)
  const hasContractData = contractValues.length > 0
  const totalContracts = hasContractData
    ? contractValues.reduce((sum, n) => sum + n, 0)
    : null
  const avgContracts =
    hasContractData && totalContracts != null
      ? totalContracts / contractValues.length
      : null

  const consistency = computeDailyConsistency(options?.dailyPnls ?? [])

  const chronological = [...list].sort(compareDashboardTradesChronological)
  const streaks = computeTradePnlStreaks(chronological)

  return {
    totalTrades: performance.totalTrades,
    winningTrades: wins.length,
    losingTrades: losses.length,
    breakEvenTrades: list.length - wins.length - losses.length,
    winRate: list.length > 0 ? performance.winRate : null,
    totalPnl: performance.totalPnL,
    avgTradePnl: list.length > 0 ? performance.totalPnL / list.length : null,
    bestTrade,
    worstTrade,
    profitFactor,
    profitFactorInfinite,
    avgRR: averageRrFromTrades(list),
    totalRR,
    avgWin,
    avgLoss,
    largestWin,
    largestLoss,
    longTrades,
    shortTrades,
    hasDirectionData,
    avgHoldSeconds: holdTime.avgHoldSeconds,
    holdTime,
    avgContracts,
    totalContracts,
    hasContractData,
    consistency,
    longestWinStreak: streaks.maxWinStreak,
    longestLossStreak: streaks.maxLossStreak,
  }
}
