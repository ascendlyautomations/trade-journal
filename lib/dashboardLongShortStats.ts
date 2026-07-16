import {
  compareDashboardTradesChronological,
  type DashboardTradeDateFields,
} from "./dashboardTradeDate"
import { averageRrFromTrades, hasStoredRr } from "./tradeRr"

export type LongShortSideStats = {
  totalTrades: number
  wins: number
  winRate: number
  totalPnL: number
  avgPnL: number
  bestTrade: number | null
  worstTrade: number | null
  profitFactor: number
  expectancy: number
  avgRR: number | null
  bestWinStreak: number
}

export type DirectionEdgeVerdict =
  | "insufficient"
  | "long"
  | "short"
  | "balanced"

export type DirectionEdge = {
  verdict: DirectionEdgeVerdict
  message: string
  longExpectancy: number | null
  shortExpectancy: number | null
  longProfitFactor: number | null
  shortProfitFactor: number | null
  longAvgRR: number | null
  shortAvgRR: number | null
}

export type LongShortPerformance = {
  long: LongShortSideStats | null
  short: LongShortSideStats | null
  directionEdge: DirectionEdge
  /** True when at least one trade has a recognized Long or Short direction. */
  hasDirectionData: boolean
}

export type LongShortTradeRow = DashboardTradeDateFields & {
  direction?: unknown
  pnl?: unknown
  rr?: unknown
}

const DIRECTION_EDGE_MIN_TRADES = 5

export function normalizeTradeDirection(
  raw: unknown
): "Long" | "Short" | null {
  const s = String(raw ?? "").trim().toLowerCase()
  if (!s) return null
  if (s === "long" || s === "buy") return "Long"
  if (s === "short" || s === "sell") return "Short"
  return null
}

export const isValidTradeRR = hasStoredRr

/** sum(rr) / trades with valid rr; missing RR excluded from denominator. */
export const computeSideAvgRR = averageRrFromTrades

/** Matches dashboard grossProfit / grossLoss profit factor. */
export function computeSideProfitFactor(trades: { pnl?: unknown }[]): number {
  const grossProfit = trades
    .filter((t) => (Number(t.pnl) || 0) > 0)
    .reduce((sum, t) => sum + (Number(t.pnl) || 0), 0)

  const grossLoss = trades
    .filter((t) => (Number(t.pnl) || 0) < 0)
    .reduce((sum, t) => sum + Math.abs(Number(t.pnl) || 0), 0)

  return grossLoss === 0 ? 0 : grossProfit / grossLoss
}

/** Matches dashboard calculateExpectancy formula. */
export function computeSideExpectancy(trades: { pnl?: unknown }[]): number {
  if (trades.length === 0) return 0

  const wins = trades.filter((t) => (Number(t.pnl) || 0) > 0)
  const losses = trades.filter((t) => (Number(t.pnl) || 0) < 0)

  const winRate = wins.length / trades.length
  const lossRate = losses.length / trades.length

  const avgWin =
    wins.length > 0
      ? wins.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0) / wins.length
      : 0

  const avgLoss =
    losses.length > 0
      ? Math.abs(
          losses.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0) /
            losses.length
        )
      : 0

  return winRate * avgWin - lossRate * avgLoss
}

/** Matches dashboard calculateStreaks (chronological order). */
export function computeTradePnlStreaks(trades: { pnl?: unknown }[]): {
  maxWinStreak: number
  maxLossStreak: number
} {
  if (trades.length === 0) {
    return { maxWinStreak: 0, maxLossStreak: 0 }
  }

  let maxWinStreak = 0
  let maxLossStreak = 0
  let tempStreak = 0
  let tempType: "win" | "loss" | "even" | null = null

  for (const trade of trades) {
    const pnl = Number(trade.pnl) || 0
    const type: "win" | "loss" | "even" =
      pnl > 0 ? "win" : pnl < 0 ? "loss" : "even"

    if (type === tempType) {
      tempStreak += 1
    } else {
      tempStreak = 1
      tempType = type
    }

    if (type === "win" && tempStreak > maxWinStreak) {
      maxWinStreak = tempStreak
    }

    if (type === "loss" && tempStreak > maxLossStreak) {
      maxLossStreak = tempStreak
    }
  }

  return { maxWinStreak, maxLossStreak }
}

/** Matches dashboard calculateStreaks maxWinStreak (chronological order). */
export function computeSideMaxWinStreak(trades: { pnl?: unknown }[]): number {
  return computeTradePnlStreaks(trades).maxWinStreak
}

export function computeDirectionEdge(
  long: LongShortSideStats | null,
  short: LongShortSideStats | null
): DirectionEdge {
  const longExpectancy = long?.expectancy ?? null
  const shortExpectancy = short?.expectancy ?? null
  const longProfitFactor = long?.profitFactor ?? null
  const shortProfitFactor = short?.profitFactor ?? null
  const longAvgRR = long?.avgRR ?? null
  const shortAvgRR = short?.avgRR ?? null

  const insufficientMessage =
    "More trade data is needed to determine a directional edge."

  if (
    !long ||
    !short ||
    long.totalTrades < DIRECTION_EDGE_MIN_TRADES ||
    short.totalTrades < DIRECTION_EDGE_MIN_TRADES
  ) {
    return {
      verdict: "insufficient",
      message: insufficientMessage,
      longExpectancy,
      shortExpectancy,
      longProfitFactor,
      shortProfitFactor,
      longAvgRR,
      shortAvgRR,
    }
  }

  let longScore = 0
  let shortScore = 0

  if (long.expectancy > short.expectancy) longScore += 1
  else if (short.expectancy > long.expectancy) shortScore += 1

  if (long.profitFactor > short.profitFactor) longScore += 1
  else if (short.profitFactor > long.profitFactor) shortScore += 1

  if (long.totalPnL > short.totalPnL) longScore += 1
  else if (short.totalPnL > long.totalPnL) shortScore += 1

  let verdict: DirectionEdgeVerdict = "balanced"
  let message = "Long and Short performance are currently balanced."

  if (longScore >= 2 && longScore > shortScore) {
    verdict = "long"
    message = "You are significantly more profitable trading Long."
  } else if (shortScore >= 2 && shortScore > longScore) {
    verdict = "short"
    message = "You are significantly more profitable trading Short."
  }

  return {
    verdict,
    message,
    longExpectancy,
    shortExpectancy,
    longProfitFactor,
    shortProfitFactor,
    longAvgRR,
    shortAvgRR,
  }
}

function finalizeSide(
  agg: SideAgg,
  sideTrades: LongShortTradeRow[]
): LongShortSideStats | null {
  if (agg.totalTrades === 0) return null

  const chronological = [...sideTrades].sort(compareDashboardTradesChronological)

  return {
    totalTrades: agg.totalTrades,
    wins: agg.wins,
    winRate: (agg.wins / agg.totalTrades) * 100,
    totalPnL: agg.totalPnL,
    avgPnL: agg.totalPnL / agg.totalTrades,
    bestTrade: agg.bestTrade,
    worstTrade: agg.worstTrade,
    profitFactor: computeSideProfitFactor(sideTrades),
    expectancy: computeSideExpectancy(sideTrades),
    avgRR: computeSideAvgRR(sideTrades),
    bestWinStreak: computeSideMaxWinStreak(chronological),
  }
}

type SideAgg = {
  totalTrades: number
  wins: number
  totalPnL: number
  bestTrade: number | null
  worstTrade: number | null
}

function newSideAgg(): SideAgg {
  return {
    totalTrades: 0,
    wins: 0,
    totalPnL: 0,
    bestTrade: null,
    worstTrade: null,
  }
}

export function computeLongShortPerformance(
  trades: LongShortTradeRow[]
): LongShortPerformance {
  const longAgg = newSideAgg()
  const shortAgg = newSideAgg()
  const longTrades: LongShortTradeRow[] = []
  const shortTrades: LongShortTradeRow[] = []

  let hasDirectionData = false

  for (const trade of trades) {
    const side = normalizeTradeDirection(trade.direction)
    if (!side) continue

    hasDirectionData = true
    const pnl = Number(trade.pnl) || 0
    const agg = side === "Long" ? longAgg : shortAgg
    const bucket = side === "Long" ? longTrades : shortTrades

    bucket.push(trade)
    agg.totalTrades += 1
    agg.totalPnL += pnl
    if (pnl > 0) agg.wins += 1

    if (agg.bestTrade === null || pnl > agg.bestTrade) {
      agg.bestTrade = pnl
    }
    if (agg.worstTrade === null || pnl < agg.worstTrade) {
      agg.worstTrade = pnl
    }
  }

  const long = finalizeSide(longAgg, longTrades)
  const short = finalizeSide(shortAgg, shortTrades)

  return {
    long,
    short,
    directionEdge: computeDirectionEdge(long, short),
    hasDirectionData,
  }
}
