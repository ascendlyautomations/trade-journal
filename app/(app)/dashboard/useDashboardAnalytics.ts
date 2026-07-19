"use client"

import { useMemo } from "react"
import { tradeMatchesAccountFilter } from "@/lib/tradeAccountDisplay"
import { devLog } from "@/lib/devLog"
import {
  getTradingSession,
  getTradingWeekday,
} from "@/lib/formatDate"
import {
  computeLongShortPerformance,
  type LongShortPerformance,
} from "@/lib/dashboardLongShortStats"
import { averageRrFromTrades, hasStoredRr } from "@/lib/tradeRr"
import {
  computeHoldTimeStats,
  type HoldTimeStats,
} from "@/lib/dashboardHoldTimeStats"
import { computeMaxDrawdown } from "@/lib/dashboardMaxDrawdown"
import {
  compareDashboardTradesChronological,
  getDashboardTradingDayKey,
  resolveDashboardTradeTimeSource,
  tradeMatchesDashboardSelectedDate,
  tradeMatchesDashboardTimeFilter,
} from "@/lib/dashboardTradeDate"
import {
  DASHBOARD_SESSION_DISPLAY_ORDER,
  normalizeSessionBucket,
} from "@/lib/dashboardSessionBuckets"
import type {
  DashboardAccountRow,
  DashboardTradeRow,
} from "@/app/components/dashboard/dashboardTypes"

type SetupGroupResult = {
  type: string
  value: string
  totalPnL: number
  trades: number
  wins: number
  avgPnL: number
  winRate: number
}

function analyzeBestSetups(trades: DashboardTradeRow[]): SetupGroupResult[] {
  const groupStats: Record<
    string,
    { type: string; value: string; totalPnL: number; trades: number; wins: number }
  > = {}

  trades.forEach((trade) => {
    const { session, ticker, direction } = trade
    const pnl = Number(trade.pnl) || 0

    const groups = [
      { type: "session", value: session ?? "—" },
      { type: "ticker", value: ticker ?? "—" },
      { type: "direction", value: direction ?? "—" },
    ]

    groups.forEach(({ type, value }) => {
      const key = `${type}:${value}`

      if (!groupStats[key]) {
        groupStats[key] = {
          type,
          value: String(value),
          totalPnL: 0,
          trades: 0,
          wins: 0,
        }
      }

      groupStats[key].totalPnL += pnl
      groupStats[key].trades += 1
      if (pnl > 0) groupStats[key].wins += 1
    })
  })

  return Object.values(groupStats)
    .map((g) => ({
      ...g,
      avgPnL: g.trades ? g.totalPnL / g.trades : 0,
      winRate: g.trades ? g.wins / g.trades : 0,
    }))
    .filter((g) => g.trades >= 3)
    .sort((a, b) => b.avgPnL - a.avgPnL)
}

function formatPerformanceInsightMoney(v: number) {
  const abs = Math.abs(v)
  const formatted = abs.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  return v < 0 ? `-$${formatted}` : `$${formatted}`
}

function generateInsights(results: SetupGroupResult[]): string[] {
  if (!results.length) return []

  const insights: string[] = []

  const bestSession = results.find((r) => r.type === "session")
  const bestTicker = results.find((r) => r.type === "ticker")
  const bestDirection = results.find((r) => r.type === "direction")

  const formatPct = (v: number) => `${(v * 100).toFixed(0)}%`

  if (bestSession && bestSession.value !== "—") {
    insights.push(
      `You perform best trading ${bestSession.value} session (${formatPerformanceInsightMoney(
        bestSession.avgPnL
      )} avg, ${formatPct(bestSession.winRate)} win rate)`
    )
  }

  if (bestTicker && bestTicker.value !== "—") {
    insights.push(
      `${bestTicker.value} is your most profitable market (${formatPerformanceInsightMoney(
        bestTicker.avgPnL
      )} avg per trade)`
    )
  }

  if (bestDirection && bestDirection.value !== "—") {
    insights.push(
      `You are more profitable going ${bestDirection.value} (${formatPerformanceInsightMoney(
        bestDirection.avgPnL
      )} avg)`
    )
  }

  return insights
}

type CombinedSetupResult = {
  key: string
  totalPnL: number
  trades: number
  wins: number
  avgPnL: number
  winRate: number
}

function analyzeCombinedSetups(trades: DashboardTradeRow[]): CombinedSetupResult[] {
  const stats: Record<
    string,
    { key: string; totalPnL: number; trades: number; wins: number }
  > = {}

  trades.forEach((trade) => {
    const { session, ticker, direction } = trade
    const pnl = Number(trade.pnl) || 0

    const s = session ?? "—"
    const t = ticker ?? "—"
    const d = direction ?? "—"

    const combos = [
      `session:${s}|ticker:${t}`,
      `session:${s}|direction:${d}`,
      `ticker:${t}|direction:${d}`,
      `session:${s}|ticker:${t}|direction:${d}`,
    ]

    combos.forEach((key) => {
      if (!stats[key]) {
        stats[key] = { key, totalPnL: 0, trades: 0, wins: 0 }
      }
      stats[key].totalPnL += pnl
      stats[key].trades += 1
      if (pnl > 0) stats[key].wins += 1
    })
  })

  return Object.values(stats)
    .map((row) => ({
      ...row,
      avgPnL: row.trades ? row.totalPnL / row.trades : 0,
      winRate: row.trades ? row.wins / row.trades : 0,
    }))
    .filter((row) => row.trades >= 3)
    .sort((a, b) => b.avgPnL - a.avgPnL)
}

function formatCombo(key: string): string {
  const parts = key.split("|").map((p) => {
    const idx = p.indexOf(":")
    return idx >= 0 ? p.slice(idx + 1) : p
  })

  if (parts.length === 2) {
    return `${parts[1]} during ${parts[0]}`
  }

  if (parts.length === 3) {
    return `${parts[1]} during ${parts[0]} going ${parts[2]}`
  }

  return parts.filter(Boolean).join(" ")
}

function generateCombinedInsights(results: CombinedSetupResult[]): string[] {
  const meaningful = results.filter(
    (r) => !r.key.includes("—") && !r.key.includes("undefined")
  )
  if (!meaningful.length) return []

  const formatPct = (v: number) => `${(v * 100).toFixed(0)}%`

  const best = meaningful[0]

  return [
    `Your strongest setup is trading ${formatCombo(
      best.key
    )} (${formatPerformanceInsightMoney(best.avgPnL)} avg, ${formatPct(
      best.winRate
    )} win rate over ${best.trades} trades)`,
  ]
}

function generateWorstInsight(worst: CombinedSetupResult | undefined): string | null {
  if (!worst) return null

  const formatPct = (v: number) => `${(v * 100).toFixed(0)}%`

  return `You struggle most trading ${formatCombo(
    worst.key
  )} (${formatPerformanceInsightMoney(worst.avgPnL)} avg, ${formatPct(
    worst.winRate
  )} win rate over ${worst.trades} trades)`
}

function detectLossStreak(trades: DashboardTradeRow[]): number | null {
  if (trades.length < 4) return null

  for (let i = 0; i <= trades.length - 4; i++) {
    const a = Number(trades[i].pnl) || 0
    const b = Number(trades[i + 1].pnl) || 0
    const c = Number(trades[i + 2].pnl) || 0

    if (a < 0 && b < 0 && c < 0) {
      const nextTrades = trades.slice(i + 3, i + 8)
      if (nextTrades.length === 0) return null

      const wins = nextTrades.filter((t) => (Number(t.pnl) || 0) > 0).length
      return wins / nextTrades.length
    }
  }

  return null
}

function detectRRThreshold(trades: DashboardTradeRow[]): string | null {
  const lowRR = trades.filter((t) => {
    if (!hasStoredRr(t.rr)) return false
    return Number(t.rr) < 1
  })
  const highRR = trades.filter((t) => {
    if (!hasStoredRr(t.rr)) return false
    return Number(t.rr) >= 1
  })

  if (lowRR.length < 3 || highRR.length < 3) return null

  const lowWin = lowRR.filter((t) => (Number(t.pnl) || 0) > 0).length / lowRR.length
  const highWin =
    highRR.filter((t) => (Number(t.pnl) || 0) > 0).length / highRR.length

  if (highWin > lowWin + 0.2) {
    return "You perform significantly better when RR ≥ 1"
  }

  return null
}

function calculateExpectancy(trades: DashboardTradeRow[]) {
  if (!trades || trades.length === 0) return null

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

  const expectancy = winRate * avgWin - lossRate * avgLoss

  return {
    expectancy,
    winRate,
    avgWin,
    avgLoss,
  }
}

function calculateStreaks(trades: DashboardTradeRow[]) {
  if (!trades || trades.length === 0) return null

  let currentStreak = 0
  let currentType: "win" | "loss" | "even" | null = null

  let maxWinStreak = 0
  let maxLossStreak = 0

  let tempStreak = 0
  let tempType: "win" | "loss" | "even" | null = null

  trades.forEach((trade) => {
    const pnl = Number(trade.pnl) || 0
    const type: "win" | "loss" | "even" =
      pnl > 0 ? "win" : pnl < 0 ? "loss" : "even"

    if (type === tempType) {
      tempStreak++
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

    currentStreak = tempStreak
    currentType = tempType
  })

  return {
    currentStreak,
    currentType,
    maxWinStreak,
    maxLossStreak,
  }
}

export type TradingHoursSummary = {
  hourlyMap: Record<number, number>
  hasValidTradingHoursData: boolean
  bestHour: number | null
  worstHour: number | null
}

/** Hour from entry/exit time: full datetime, or HH:MM / HH:MM:SS. */
function parseHourFromEntryOrExit(timeSource: unknown): number | null {
  if (timeSource == null || timeSource === "") return null
  const raw = String(timeSource).trim()
  if (!raw) return null

  const date = new Date(raw)
  if (!Number.isNaN(date.getTime())) {
    return date.getHours()
  }

  const m = raw.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/)
  if (!m) return null
  const h = parseInt(m[1], 10)
  if (!Number.isFinite(h) || h < 0 || h > 23) return null
  return h
}

function analyzeTradingHours(trades: DashboardTradeRow[]): TradingHoursSummary | null {
  if (!trades || trades.length === 0) return null

  const hourlyMap: Record<number, number> = {}

  trades.forEach((trade) => {
    const timeSource = resolveDashboardTradeTimeSource(trade)
    if (!timeSource) return

    const hour = parseHourFromEntryOrExit(timeSource)
    if (hour === null) return

    hourlyMap[hour] = (hourlyMap[hour] || 0) + (Number(trade.pnl) || 0)
  })

  const hasValidTradingHoursData = Object.keys(hourlyMap).length > 1

  let bestHour: number | null = null
  let worstHour: number | null = null

  if (hasValidTradingHoursData) {
    const rows = Object.entries(hourlyMap).map(([h, pnl]) => ({
      hour: Number(h),
      pnl,
    }))
    rows.sort((a, b) => b.pnl - a.pnl)
    bestHour = rows[0].hour
    worstHour = rows[rows.length - 1].hour
  }

  return {
    hourlyMap,
    hasValidTradingHoursData,
    bestHour,
    worstHour,
  }
}

export type DashboardSymbolPerformanceRow = {
  ticker: string
  totalTrades: number
  wins: number
  winRate: number
  totalPnL: number
  avgRR: number | null
}

export type DashboardBestSetup = {
  strategy: string
  trades: number
  winRate: number
  totalPnL: number
}

export type DashboardExpectancyData = {
  expectancy: number
  winRate: number
  avgWin: number
  avgLoss: number
}

export type DashboardStreakData = {
  currentStreak: number
  currentType: "win" | "loss" | "even" | null
  maxWinStreak: number
  maxLossStreak: number
}

export type DashboardEquityPoint = {
  date: string
  equity: number
}

export type UseDashboardAnalyticsParams = {
  deferredTradesExcludingBacktest: DashboardTradeRow[]
  showPublicOnly: boolean
  accountFilter: string
  accountTypeFilter: string
  timeFilter: string
  selectedDate: string
  customRangeStart: string
  customRangeEnd: string
  accountById: Record<string, DashboardAccountRow>
  copyGroupAccountIds: string[] | null
}

export type DashboardAnalyticsResult = {
  filteredTrades: DashboardTradeRow[]
  totalTrades: number
  winRate: number
  totalPnL: number
  avgRR: number | null
  biggestLoss: number
  bestTrade: number
  avgWin: number
  avgLoss: number
  bestDay: number
  worstDay: number
  symbolPerformanceRows: DashboardSymbolPerformanceRow[]
  longShortPerformance: LongShortPerformance
  holdTimeStats: HoldTimeStats
  maxDrawdown: number
  sessionBuckets: Record<
    "London" | "NY" | "Asia",
    { totalTrades: number; wins: number; totalPnL: number }
  >
  bestSetup: DashboardBestSetup | null
  insights: string[]
  combinedInsights: string[]
  worstInsight: string | null
  warnings: string[]
  equityDrawdownChartData: DashboardEquityPoint[]
  expectancyData: DashboardExpectancyData | null
  streakData: DashboardStreakData | null
  hourData: TradingHoursSummary | null
  weekdayData: { day: "Mon" | "Tue" | "Wed" | "Thu" | "Fri"; pnl: number }[]
  sessionPieData: { name: "London" | "NY" | "Asia"; value: number }[]
  insightBestSymbol: string | null
  insightBestSymbolAvg: number
  insightBestWeekday: string | null
  insightBestWeekdayAvg: number
  hasTradingDayTimeSource: boolean
}

export function useDashboardAnalytics({
  deferredTradesExcludingBacktest,
  showPublicOnly,
  accountFilter,
  accountTypeFilter,
  timeFilter,
  selectedDate,
  customRangeStart,
  customRangeEnd,
  accountById,
  copyGroupAccountIds,
}: UseDashboardAnalyticsParams): DashboardAnalyticsResult {
  return useMemo(() => {
    if (process.env.NODE_ENV === "development") {
      devLog("Trades:", deferredTradesExcludingBacktest)
      if (deferredTradesExcludingBacktest.length)
        devLog("Sample trade:", deferredTradesExcludingBacktest[0])
    }

    /** Public trades: DB flag and/or non-empty public note (matches InputTradeForm / feed). */
    function tradeIsPublic(t: DashboardTradeRow) {
      if (t?.is_public === true) return true
      const desc = t?.public_description
      return typeof desc === "string" && desc.trim().length > 0
    }

    const now = new Date()

    const withoutPublicFilter = deferredTradesExcludingBacktest.filter((trade) => {
      if (
        selectedDate &&
        !tradeMatchesDashboardSelectedDate(trade, selectedDate)
      ) {
        return false
      }

      if (
        !tradeMatchesDashboardTimeFilter(
          trade,
          timeFilter,
          now,
          customRangeStart,
          customRangeEnd
        )
      ) {
        return false
      }

      if (
        !tradeMatchesAccountFilter(
          trade,
          accountFilter,
          accountById[String(trade.account_id ?? "").trim()],
          { copyGroupAccountIds: copyGroupAccountIds ?? undefined }
        )
      ) {
        return false
      }

      const tradeAcct = String(trade.mode ?? trade.account_type ?? "")
        .toLowerCase()
        .trim()
      const selectedAcct = accountTypeFilter.toLowerCase().trim()
      if (accountTypeFilter !== "all") {
        if (tradeAcct !== selectedAcct) {
          return false
        }
      }

      return true
    })

    let filteredTrades = withoutPublicFilter
    if (showPublicOnly) {
      const publicFiltered = withoutPublicFilter.filter((t) => tradeIsPublic(t))
      filteredTrades =
        publicFiltered.length > 0 ? publicFiltered : withoutPublicFilter
    }

    filteredTrades = filteredTrades.sort(compareDashboardTradesChronological)

    const totalTrades = filteredTrades.length
    const wins = filteredTrades.filter(t => (Number(t.pnl) || 0) > 0)
    const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
    const totalPnL = filteredTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)

    const avgRR = averageRrFromTrades(filteredTrades)

    const losses = filteredTrades
  .map(t => Number(t.pnl) || 0)
  .filter(p => p < 0)

const biggestLoss = losses.length > 0
  ? Math.min(...losses)
  : 0

    const bestTrade = filteredTrades.length
      ? Math.max(...filteredTrades.map((t) => Number(t.pnl) || 0))
      : 0

    const symbolStats: Record<
      string,
      { pnl: number; trades: number; wins: number }
    > = {}

    filteredTrades.forEach((t) => {
      const ticker = String(t.ticker)
      if (!symbolStats[ticker]) {
        symbolStats[ticker] = {
          pnl: 0,
          trades: 0,
          wins: 0
        }
      }

      symbolStats[ticker].pnl += Number(t.pnl) || 0
      symbolStats[ticker].trades += 1
      if ((Number(t.pnl) || 0) > 0) symbolStats[ticker].wins += 1
    })

    let insightBestSymbol: string | null = null
    let insightBestSymbolAvg = -Infinity
    Object.entries(symbolStats).forEach(([symbol, data]) => {
      if (!symbol || symbol === "undefined" || data.trades < 3) return
      const avg = Number(data.pnl) / data.trades
      if (avg > insightBestSymbolAvg) {
        insightBestSymbolAvg = avg
        insightBestSymbol = symbol
      }
    })

    const tickerAgg: Record<
      string,
      { totalPnL: number; wins: number; totalTrades: number; rrSum: number; rrCount: number }
    > = {}

    filteredTrades.forEach((t) => {
      const ticker = t.ticker || "—"
      if (!tickerAgg[ticker]) {
        tickerAgg[ticker] = { totalPnL: 0, wins: 0, totalTrades: 0, rrSum: 0, rrCount: 0 }
      }
      tickerAgg[ticker].totalPnL += Number(t.pnl) || 0
      tickerAgg[ticker].totalTrades += 1
      if ((Number(t.pnl) || 0) > 0) tickerAgg[ticker].wins += 1
      if (hasStoredRr(t.rr)) {
        tickerAgg[ticker].rrSum += Number(t.rr)
        tickerAgg[ticker].rrCount += 1
      }
    })

    const symbolPerformanceRows = Object.entries(tickerAgg)
      .map(([ticker, s]) => ({
        ticker,
        totalTrades: s.totalTrades,
        wins: s.wins,
        winRate: s.totalTrades ? (s.wins / s.totalTrades) * 100 : 0,
        totalPnL: s.totalPnL,
        avgRR: s.rrCount ? s.rrSum / s.rrCount : null,
      }))
      .sort((a, b) => b.totalPnL - a.totalPnL)

    const strategyAgg: Record<
      string,
      { totalPnL: number; wins: number; totalTrades: number; rrSum: number; rrCount: number }
    > = {}

    filteredTrades.forEach((t) => {
      const strategy = (t.strategy && String(t.strategy).trim()) || ""
      if (!strategy) return
      if (!strategyAgg[strategy]) {
        strategyAgg[strategy] = { totalPnL: 0, wins: 0, totalTrades: 0, rrSum: 0, rrCount: 0 }
      }
      strategyAgg[strategy].totalPnL += Number(t.pnl) || 0
      strategyAgg[strategy].totalTrades += 1
      if ((Number(t.pnl) || 0) > 0) strategyAgg[strategy].wins += 1
      if (hasStoredRr(t.rr)) {
        strategyAgg[strategy].rrSum += Number(t.rr)
        strategyAgg[strategy].rrCount += 1
      }
    })

    const strategyPerformanceRows = Object.entries(strategyAgg)
      .map(([strategy, s]) => ({
        strategy,
        totalTrades: s.totalTrades,
        wins: s.wins,
        winRate: s.totalTrades ? (s.wins / s.totalTrades) * 100 : 0,
        totalPnL: s.totalPnL,
        avgRR: s.rrCount ? s.rrSum / s.rrCount : null,
      }))
      .sort((a, b) => b.totalPnL - a.totalPnL)

    const sessionBuckets: Record<"London" | "NY" | "Asia", { totalTrades: number; wins: number; totalPnL: number }> = {
      London: { totalTrades: 0, wins: 0, totalPnL: 0 },
      NY: { totalTrades: 0, wins: 0, totalPnL: 0 },
      Asia: { totalTrades: 0, wins: 0, totalPnL: 0 }
    }

    filteredTrades.forEach((t) => {
      const b = normalizeSessionBucket(t.session)
      if (!b) return
      sessionBuckets[b].totalTrades += 1
      sessionBuckets[b].totalPnL += Number(t.pnl) || 0
      if ((Number(t.pnl) || 0) > 0) sessionBuckets[b].wins += 1
    })

    const sessionPieData = DASHBOARD_SESSION_DISPLAY_ORDER.map((name) => ({
      name,
      value: sessionBuckets[name].totalTrades,
    }))

    const weekdayMap: Record<"Mon" | "Tue" | "Wed" | "Thu" | "Fri", number> = {
      Mon: 0,
      Tue: 0,
      Wed: 0,
      Thu: 0,
      Fri: 0
    }

    const tradingLongToShort: Record<
      string,
      keyof typeof weekdayMap
    > = {
      Monday: "Mon",
      Tuesday: "Tue",
      Wednesday: "Wed",
      Thursday: "Thu",
      Friday: "Fri",
    }

    filteredTrades.forEach((t) => {
      const resolved = resolveDashboardTradeTimeSource(t)
      if (!resolved) return
      const longDay = getTradingWeekday(resolved)
      if (!longDay) return
      const short = tradingLongToShort[longDay]
      if (!short) return
      weekdayMap[short] += Number(t.pnl) || 0
    })

    const weekdayData = (["Mon", "Tue", "Wed", "Thu", "Fri"] as const).map((day) => ({
      day,
      pnl: weekdayMap[day]
    }))

    const weekdayInsightStats: Record<string, { pnl: number; trades: number }> = {}
    filteredTrades.forEach((trade) => {
      const resolved = resolveDashboardTradeTimeSource(trade)
      if (!resolved) return
      const day = getTradingWeekday(resolved)
      if (!day) return
      if (!weekdayInsightStats[day]) {
        weekdayInsightStats[day] = { pnl: 0, trades: 0 }
      }
      weekdayInsightStats[day].pnl += Number(trade.pnl) || 0
      weekdayInsightStats[day].trades += 1
    })

    let insightBestWeekday: string | null = null
    let insightBestWeekdayAvg = -Infinity
    Object.entries(weekdayInsightStats).forEach(([day, data]) => {
      if (data.trades < 2) return
      const avg = data.pnl / data.trades
      if (avg > insightBestWeekdayAvg) {
        insightBestWeekdayAvg = avg
        insightBestWeekday = day
      }
    })

    const bestStrategyRow = strategyPerformanceRows.find(
      (row) => row.totalTrades >= 3
    )
    const bestSetup = bestStrategyRow
      ? {
          strategy: bestStrategyRow.strategy,
          trades: bestStrategyRow.totalTrades,
          winRate: bestStrategyRow.winRate,
          totalPnL: bestStrategyRow.totalPnL,
        }
      : null

    const setupResults = analyzeBestSetups(filteredTrades)
    const insights = generateInsights(setupResults)

    const combinedResults = analyzeCombinedSetups(filteredTrades)
    const combinedInsights = generateCombinedInsights(combinedResults)

    const meaningfulCombined = combinedResults.filter(
      (r) => !r.key.includes("—") && !r.key.includes("undefined")
    )
    const worstResults = [...meaningfulCombined]
      .filter((r) => r.trades >= 3)
      .sort((a, b) => a.avgPnL - b.avgPnL)
    const worst = worstResults[0]
    const worstInsight = generateWorstInsight(worst)

    const chronologicalTrades = [...filteredTrades].sort(
      compareDashboardTradesChronological
    )

    const longShortPerformance = computeLongShortPerformance(filteredTrades)
    const holdTimeStats = computeHoldTimeStats(filteredTrades)
    const maxDrawdown = computeMaxDrawdown(filteredTrades)
    const streakData = calculateStreaks(chronologicalTrades)
    const expectancyData = calculateExpectancy(filteredTrades)
    const hourData = analyzeTradingHours(filteredTrades)
    const equityDrawdownChartData = chronologicalTrades.reduce<
      DashboardEquityPoint[]
    >((points, trade, index) => {
      const runningEquity =
        (points.length > 0 ? points[points.length - 1].equity : 0) +
        (Number(trade.pnl) || 0)

      if (process.env.NODE_ENV === "development" && index < 5) {
        devLog({
          equity: runningEquity,
        })
      }

      points.push({
        date:
          resolveDashboardTradeTimeSource(trade) ??
          trade.created_at ??
          "",
        equity: runningEquity,
      })
      return points
    }, [])
    const lossStreakRate = detectLossStreak(chronologicalTrades)
    const rrInsight = detectRRThreshold(filteredTrades)

    const warnings: string[] = []
    if (lossStreakRate !== null && Number.isFinite(lossStreakRate)) {
      warnings.push(
        `After 3 consecutive losses, your win rate drops to ${(
          lossStreakRate * 100
        ).toFixed(0)}% in the next few trades`
      )
    }
    if (rrInsight) {
      warnings.push(rrInsight)
    }

    const dailyMap: Record<string, number> = {}

    filteredTrades.forEach((t) => {
      const dateKey = getDashboardTradingDayKey(t)
      if (!dateKey) return
      dailyMap[dateKey] = (dailyMap[dateKey] || 0) + (Number(t.pnl) || 0)
    })

    const dailyPnLs = Object.values(dailyMap)

    const bestDay = dailyPnLs.length > 0
  ? Math.max(...dailyPnLs)
  : 0

    const worstDay = dailyPnLs.length > 0
      ? Math.min(...dailyPnLs)
      : 0

    const winsOnly = filteredTrades.filter(t => (Number(t.pnl) || 0) > 0)
    const lossesOnly = filteredTrades.filter(t => (Number(t.pnl) || 0) < 0)

    const avgWin =
      winsOnly.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0) /
      (winsOnly.length || 1)

    const avgLoss =
      lossesOnly.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0) /
      (lossesOnly.length || 1)

    const hasTradingDayTimeSource = filteredTrades.some(
      (t) => resolveDashboardTradeTimeSource(t) != null
    )

    if (process.env.NODE_ENV === "development") {
      devLog(
        filteredTrades.map((t) => ({
          pnl: t.pnl,
          session: getTradingSession(t.entry_time || t.exit_time),
        }))
      )
    }

    return {
      filteredTrades,
      totalTrades,
      winRate,
      totalPnL,
      avgRR,
      biggestLoss,
      bestTrade,
      avgWin,
      avgLoss,
      bestDay,
      worstDay,
      symbolPerformanceRows,
      longShortPerformance,
      holdTimeStats,
      maxDrawdown,
      sessionBuckets,
      bestSetup,
      insights,
      combinedInsights,
      worstInsight,
      warnings,
      equityDrawdownChartData,
      expectancyData,
      streakData,
      hourData,
      weekdayData,
      sessionPieData,
      insightBestSymbol,
      insightBestSymbolAvg,
      insightBestWeekday,
      insightBestWeekdayAvg,
      hasTradingDayTimeSource,
    }

  }, [
    deferredTradesExcludingBacktest,
    showPublicOnly,
    accountFilter,
    accountTypeFilter,
    timeFilter,
    selectedDate,
    customRangeStart,
    customRangeEnd,
    accountById,
    copyGroupAccountIds,
  ])
}
