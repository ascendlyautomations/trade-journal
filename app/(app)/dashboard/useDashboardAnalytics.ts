"use client"

import { useEffect, useMemo, useState } from "react"
import {
  COMPARATIVE_MIN_PER_SIDE,
  easternHour,
  knownPnl,
  qualifiedExtreme,
} from "@/lib/analytics/knownPnl"
import { supabase } from "@/lib/supabaseClient"
import {
  complianceTradeFromRow,
  currentPsychologyRules,
  evaluatePreferenceCompliance,
  preferenceComplianceLines,
  type PreferenceRuleContext,
} from "@/lib/analytics/preferenceCompliance"
import {
  loadTradingPreferenceBundle,
} from "@/lib/analytics/tradingPreferencesStore"
import { applyPublicVisibilityFilter } from "@/lib/analytics/publicTradeFilter"
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
import {
  computeDashboardRrTargetAnalysis,
  type DashboardRrTargetAnalysis,
} from "@/lib/dashboardRrTargetAnalysis"
import { averageMaxRrReachedFromTrades, hasStoredRr } from "@/lib/tradeRr"
import {
  averageRealizedRrFromTrades,
  averageTargetedRrFromTrades,
  resolveRealizedRr,
} from "@/lib/tradePointsAndRealizedRr"
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
import { formatDashboardEquityCurvePointDate } from "@/lib/dashboardLiveAccountValue"
import {
  DASHBOARD_SESSION_DISPLAY_ORDER,
  normalizeSessionBucket,
  type DashboardSessionBucket,
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
    const pnl = knownPnl(trade.pnl)
    if (pnl == null) return

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
  const formatPct = (v: number) => `${(v * 100).toFixed(0)}%`
  const ofType = (type: string) =>
    results.filter((row) => row.type === type && row.value !== "—")

  const bestSession = qualifiedExtreme(ofType("session"), "best")
  const bestTicker = qualifiedExtreme(ofType("ticker"), "best")
  const bestDirection = qualifiedExtreme(ofType("direction"), "best")

  if (bestSession) {
    insights.push(
      `You perform best trading ${bestSession.value} session (${formatPerformanceInsightMoney(
        bestSession.avgPnL
      )} avg, ${formatPct(bestSession.winRate)} win rate)`
    )
  }

  if (bestTicker) {
    insights.push(
      `${bestTicker.value} is your most profitable market (${formatPerformanceInsightMoney(
        bestTicker.avgPnL
      )} avg per trade)`
    )
  }

  if (bestDirection) {
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
    const pnl = knownPnl(trade.pnl)
    if (pnl == null) return

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
    (row) => !row.key.includes("—") && !row.key.includes("undefined")
  )
  const best = qualifiedExtreme(meaningful, "best")
  if (!best) return []

  const formatPct = (v: number) => `${(v * 100).toFixed(0)}%`
  return [
    `Your strongest setup is trading ${formatCombo(
      best.key
    )} (${formatPerformanceInsightMoney(best.avgPnL)} avg, ${formatPct(
      best.winRate
    )} win rate over ${best.trades} trades)`,
  ]
}

function generateWorstInsight(results: CombinedSetupResult[]): string | null {
  const meaningful = results.filter(
    (row) => !row.key.includes("—") && !row.key.includes("undefined")
  )
  const worst = qualifiedExtreme(meaningful, "worst")
  if (!worst) return null

  const formatPct = (v: number) => `${(v * 100).toFixed(0)}%`
  return `You struggle most trading ${formatCombo(
    worst.key
  )} (${formatPerformanceInsightMoney(worst.avgPnL)} avg, ${formatPct(
    worst.winRate
  )} win rate over ${worst.trades} trades)`
}

function detectLossStreak(trades: DashboardTradeRow[], streakLength = 3): number | null {
  const priced = trades.flatMap((trade) => {
    const pnl = knownPnl(trade.pnl)
    return pnl == null ? [] : [pnl]
  })
  if (priced.length < COMPARATIVE_MIN_PER_SIDE + streakLength) return null

  for (let i = 0; i <= priced.length - streakLength; i++) {
    if (!priced.slice(i, i + streakLength).every((pnl) => pnl < 0)) continue
    const next = priced.slice(i + streakLength, i + streakLength + COMPARATIVE_MIN_PER_SIDE)
    if (next.length < COMPARATIVE_MIN_PER_SIDE) return null
    const nextRate = next.filter((pnl) => pnl > 0).length / next.length
    const baseline = priced.filter((pnl) => pnl > 0).length / priced.length
    if (nextRate <= baseline - 0.08) return nextRate
    return null
  }

  return null
}

function detectRRThreshold(trades: DashboardTradeRow[]): string | null {
  const priced = (rows: DashboardTradeRow[]) =>
    rows.flatMap((trade) => {
      const pnl = knownPnl(trade.pnl)
      return pnl == null ? [] : [pnl]
    })
  const lowRR = priced(
    trades.filter((t) => hasStoredRr(t.rr) && Number(t.rr) < 1)
  )
  const highRR = priced(
    trades.filter((t) => hasStoredRr(t.rr) && Number(t.rr) >= 1)
  )

  if (
    lowRR.length < COMPARATIVE_MIN_PER_SIDE ||
    highRR.length < COMPARATIVE_MIN_PER_SIDE
  ) {
    return null
  }

  const lowWin = lowRR.filter((pnl) => pnl > 0).length / lowRR.length
  const highWin = highRR.filter((pnl) => pnl > 0).length / highRR.length

  if (highWin > lowWin + 0.2 && highWin > lowWin) {
    return "Win rate is higher on trades with R at least 1 than on trades below 1"
  }

  return null
}

function calculateExpectancy(trades: DashboardTradeRow[]) {
  const priced = trades.flatMap((trade) => {
    const pnl = knownPnl(trade.pnl)
    return pnl == null ? [] : [pnl]
  })
  if (priced.length === 0) return null

  const wins = priced.filter((pnl) => pnl > 0)
  const losses = priced.filter((pnl) => pnl < 0)
  const winRate = wins.length / priced.length
  const lossRate = losses.length / priced.length
  const avgWin = wins.length
    ? wins.reduce((sum, pnl) => sum + pnl, 0) / wins.length
    : 0
  const avgLoss = losses.length
    ? Math.abs(losses.reduce((sum, pnl) => sum + pnl, 0) / losses.length)
    : 0

  return {
    expectancy: winRate * avgWin - lossRate * avgLoss,
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
    const pnl = knownPnl(trade.pnl)
    if (pnl == null) return
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
    return easternHour(date)
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

    const pnl = knownPnl(trade.pnl)
    if (pnl == null) return
    hourlyMap[hour] = (hourlyMap[hour] || 0) + pnl
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
  userId?: string | null
}

export type DashboardAnalyticsResult = {
  filteredTrades: DashboardTradeRow[]
  totalTrades: number
  winRate: number
  totalPnL: number
  avgRR: number | null
  avgMaxRrReached: number | null
  rrTargetAnalysis: DashboardRrTargetAnalysis
  biggestLoss: number
  bestTrade: number
  avgWin: number
  avgLoss: number
  winCount: number
  lossCount: number
  bestDay: number
  worstDay: number
  /** Distinct futures trading days in the filtered period (same keys as daily P&L). */
  periodTradingDayCount: number
  symbolPerformanceRows: DashboardSymbolPerformanceRow[]
  longShortPerformance: LongShortPerformance
  holdTimeStats: HoldTimeStats
  maxDrawdown: number
  sessionBuckets: Record<
    DashboardSessionBucket,
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
  sessionPieData: { name: DashboardSessionBucket; value: number }[]
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
  userId,
}: UseDashboardAnalyticsParams): DashboardAnalyticsResult {
  const [preferences, setPreferences] = useState<PreferenceRuleContext | null>(null)
  useEffect(() => {
    if (!userId) {
      setPreferences(null)
      return
    }
    let cancelled = false
    void (async () => {
      try {
        const bundle = await loadTradingPreferenceBundle(supabase, userId)
        if (!cancelled) setPreferences(bundle)
      } catch {
        if (!cancelled) setPreferences(null)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [userId])

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

    const filteredTrades = applyPublicVisibilityFilter(
      withoutPublicFilter,
      showPublicOnly,
      tradeIsPublic
    ).sort(compareDashboardTradesChronological)

    const pricedPnls = filteredTrades.flatMap((trade) => {
      const pnl = knownPnl(trade.pnl)
      return pnl == null ? [] : [pnl]
    })
    const totalTrades = filteredTrades.length
    const wins = pricedPnls.filter((pnl) => pnl > 0)
    const winRate = pricedPnls.length ? (wins.length / pricedPnls.length) * 100 : 0
    const totalPnL = pricedPnls.reduce((sum, pnl) => sum + pnl, 0)

    const avgRR = averageTargetedRrFromTrades(filteredTrades)
    const avgMaxRrReached = averageMaxRrReachedFromTrades(filteredTrades)
    const rrTargetAnalysis = computeDashboardRrTargetAnalysis(filteredTrades)

    const losses = pricedPnls.filter((pnl) => pnl < 0)

    const biggestLoss = losses.length > 0 ? Math.min(...losses) : 0

    const bestTrade = pricedPnls.length ? Math.max(...pricedPnls) : 0

    const symbolStats: Record<
      string,
      { pnl: number; trades: number; wins: number }
    > = {}

    filteredTrades.forEach((t) => {
      const ticker = String(t.ticker)
      const pnl = knownPnl(t.pnl)
      if (!ticker || ticker === "undefined" || pnl == null) return
      if (!symbolStats[ticker]) {
        symbolStats[ticker] = { pnl: 0, trades: 0, wins: 0 }
      }
      symbolStats[ticker].pnl += pnl
      symbolStats[ticker].trades += 1
      if (pnl > 0) symbolStats[ticker].wins += 1
    })

    const symbolLead = qualifiedExtreme(
      Object.entries(symbolStats).map(([symbol, data]) => ({
        symbol,
        avgPnL: data.trades ? data.pnl / data.trades : 0,
        trades: data.trades,
      })),
      "best"
    )
    const insightBestSymbol = symbolLead?.symbol ?? null
    const insightBestSymbolAvg = symbolLead?.avgPnL ?? 0

    const tickerAgg: Record<
      string,
      { totalPnL: number; wins: number; totalTrades: number; rrSum: number; rrCount: number }
    > = {}

    filteredTrades.forEach((t) => {
      const ticker = t.ticker || "—"
      const pnl = knownPnl(t.pnl)
      if (pnl == null) return
      if (!tickerAgg[ticker]) {
        tickerAgg[ticker] = { totalPnL: 0, wins: 0, totalTrades: 0, rrSum: 0, rrCount: 0 }
      }
      tickerAgg[ticker].totalPnL += pnl
      tickerAgg[ticker].totalTrades += 1
      if (pnl > 0) tickerAgg[ticker].wins += 1
      const realized = resolveRealizedRr(t)
      if (realized != null) {
        tickerAgg[ticker].rrSum += realized
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
      const pnl = knownPnl(t.pnl)
      if (pnl == null) return
      if (!strategyAgg[strategy]) {
        strategyAgg[strategy] = { totalPnL: 0, wins: 0, totalTrades: 0, rrSum: 0, rrCount: 0 }
      }
      strategyAgg[strategy].totalPnL += pnl
      strategyAgg[strategy].totalTrades += 1
      if (pnl > 0) strategyAgg[strategy].wins += 1
      const realized = resolveRealizedRr(t)
      if (realized != null) {
        strategyAgg[strategy].rrSum += realized
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

    const sessionBuckets = Object.fromEntries(
      DASHBOARD_SESSION_DISPLAY_ORDER.map((name) => [
        name,
        { totalTrades: 0, wins: 0, totalPnL: 0 },
      ])
    ) as Record<
      DashboardSessionBucket,
      { totalTrades: number; wins: number; totalPnL: number }
    >

    filteredTrades.forEach((t) => {
      const b = normalizeSessionBucket(t.session)
      if (!b) return
      sessionBuckets[b].totalTrades += 1
      const pnl = knownPnl(t.pnl)
      if (pnl == null) return
      sessionBuckets[b].totalPnL += pnl
      if (pnl > 0) sessionBuckets[b].wins += 1
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
      const pnl = knownPnl(t.pnl)
      if (pnl == null) return
      weekdayMap[short] += pnl
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
      const pnl = knownPnl(trade.pnl)
      if (pnl == null) return
      if (!weekdayInsightStats[day]) {
        weekdayInsightStats[day] = { pnl: 0, trades: 0 }
      }
      weekdayInsightStats[day].pnl += pnl
      weekdayInsightStats[day].trades += 1
    })

    const weekdayLead = qualifiedExtreme(
      Object.entries(weekdayInsightStats).map(([day, data]) => ({
        day,
        avgPnL: data.trades ? data.pnl / data.trades : 0,
        trades: data.trades,
      })),
      "best"
    )
    const insightBestWeekday = weekdayLead?.day ?? null
    const insightBestWeekdayAvg = weekdayLead?.avgPnL ?? 0

    const qualifiedStrategies = strategyPerformanceRows.filter(
      (row) => row.totalTrades >= COMPARATIVE_MIN_PER_SIDE && row.totalPnL > 0
    )
    const bestStrategyRow =
      qualifiedStrategies.length >= 2 ? qualifiedStrategies[0] : null
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

    const worstInsight = generateWorstInsight(combinedResults)

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
      const pnl = knownPnl(trade.pnl)
      if (pnl == null) return points
      const runningEquity =
        (points.length > 0 ? points[points.length - 1].equity : 0) + pnl

      if (process.env.NODE_ENV === "development" && index < 5) {
        devLog({
          equity: runningEquity,
        })
      }

      points.push({
        date: formatDashboardEquityCurvePointDate(trade),
        equity: runningEquity,
      })
      return points
    }, [])
    const pause = currentPsychologyRules(preferences).consecutiveLossPause
    const lossStreakRate = detectLossStreak(chronologicalTrades, pause ?? 3)
    const rrInsight = detectRRThreshold(filteredTrades)

    const warnings: string[] = []
    if (lossStreakRate !== null && Number.isFinite(lossStreakRate)) {
      const rate = `${(lossStreakRate * 100).toFixed(0)}%`
      warnings.push(
        pause != null
          ? `After your pause of ${pause} consecutive losses, win rate on the next priced trades was ${rate}, below the rest of this sample.`
          : `After 3 consecutive losses, your win rate drops to ${rate} in the next few trades`
      )
    }
    if (rrInsight) {
      warnings.push(rrInsight)
    }
    const preferenceRows = filteredTrades.flatMap((trade) => {
      const row = complianceTradeFromRow(trade)
      return row ? [row] : []
    })
    warnings.push(
      ...preferenceComplianceLines(evaluatePreferenceCompliance(preferenceRows, preferences))
    )

    const dailyMap: Record<string, number> = {}

    filteredTrades.forEach((t) => {
      const dateKey = getDashboardTradingDayKey(t)
      if (!dateKey) return
      const pnl = knownPnl(t.pnl)
      if (pnl == null) return
      dailyMap[dateKey] = (dailyMap[dateKey] || 0) + pnl
    })

    const dailyPnLs = Object.values(dailyMap)
    const periodTradingDayCount = Object.keys(dailyMap).length

    const bestDay = dailyPnLs.length > 0
  ? Math.max(...dailyPnLs)
  : 0

    const worstDay = dailyPnLs.length > 0
      ? Math.min(...dailyPnLs)
      : 0

    const winsOnly = pricedPnls.filter((pnl) => pnl > 0)
    const lossesOnly = pricedPnls.filter((pnl) => pnl < 0)

    const avgWin = winsOnly.length
      ? winsOnly.reduce((sum, pnl) => sum + pnl, 0) / winsOnly.length
      : 0

    const avgLoss = lossesOnly.length
      ? lossesOnly.reduce((sum, pnl) => sum + pnl, 0) / lossesOnly.length
      : 0

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
      avgMaxRrReached,
      rrTargetAnalysis,
      biggestLoss,
      bestTrade,
      avgWin,
      avgLoss,
      winCount: winsOnly.length,
      lossCount: lossesOnly.length,
      bestDay,
      worstDay,
      periodTradingDayCount,
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
    preferences,
  ])
}
