"use client"

import DashboardFilters from "../../components/dashboard/DashboardFilters"
import DashboardHeader from "../../components/dashboard/DashboardHeader"
import GettingStartedChecklist from "../../components/dashboard/GettingStartedChecklist"
import DashboardStatsGrid from "../../components/dashboard/DashboardStatsGrid"
import DashboardEquityCurve from "../../components/dashboard/DashboardEquityCurve"
import DashboardWeekdayChart from "../../components/dashboard/DashboardWeekdayChart"
import DashboardSessionChart from "../../components/dashboard/DashboardSessionChart"
import type {
  DashboardGearPersistedPrefs,
  GearDraftState,
} from "../../components/dashboard/dashboardGearTypes"
import {
  finalizeDrawdownLimitInput,
  sanitizeDashboardAccountFilter,
  sanitizeHydratedDashboardFilters,
  sanitizeDrawdownLimitInput,
} from "../../components/dashboard/dashboardGearUtils"
import PerformanceShareModal from "../../components/PerformanceShareModal"
import PostSetupImportModal from "../../components/PostSetupImportModal"
import LockedFeature from "../../components/LockedFeature"
import EmptyState from "../../components/ui/EmptyState"
import { SkeletonDashboardPage } from "../../components/ui/skeletons"
import Link from "next/link"
import { useCallback, useEffect, useState, useMemo, useRef } from "react"
import {
  mirrorAccountSettingsMaxDrawdownLimit,
} from "@/lib/profileSplitMirrorWrites"
import { supabase } from "../../../lib/supabaseClient"
import { isProActive } from "../../../lib/subscription"
import { filterTradesForPerformanceSharePool } from "@/lib/performanceShare"
import { excludeBacktestTrades } from "@/lib/tradeModeFilters"
import { formatEST } from "@/lib/formatEST"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatRR } from "@/lib/formatDisplay"
import {
  getTradingDayKey,
  getTradingSession,
  getTradingWeekday,
  resolveTradingTimeSourceForKey,
} from "@/lib/formatDate"
import {
  dispatchGettingStartedSignalsRefresh,
  notifyGettingStartedChecklistMaybeCompleted,
} from "@/lib/gettingStartedProgressSync"
import { shouldShowGettingStartedChecklist } from "@/lib/gettingStartedChecklist"
import { useGettingStartedProgress } from "@/lib/GettingStartedProgressProvider"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
const DASHBOARD_GEAR_PREFS_KEY = "tradetrax_dashboard_prefs_v1"

function loadDashboardGearPrefs(): Partial<DashboardGearPersistedPrefs> | null {
  if (typeof window === "undefined") return null
  try {
    const s = window.localStorage.getItem(DASHBOARD_GEAR_PREFS_KEY)
    if (!s) return null
    const p = JSON.parse(s) as Partial<DashboardGearPersistedPrefs>
    return p && typeof p === "object" ? p : null
  } catch {
    return null
  }
}

function saveDashboardGearPrefs(p: DashboardGearPersistedPrefs) {
  try {
    window.localStorage.setItem(DASHBOARD_GEAR_PREFS_KEY, JSON.stringify(p))
  } catch {
    /* ignore quota / private mode */
  }
}

function normalizeSessionBucket(sessionRaw: string | null | undefined): "London" | "NY" | "Asia" | null {
  const s = (sessionRaw || "").trim().toLowerCase()
  if (s === "london") return "London"
  if (s === "asia") return "Asia"
  if (s === "ny" || s === "new york") return "NY"
  return null
}

type SetupGroupResult = {
  type: string
  value: string
  totalPnL: number
  trades: number
  wins: number
  avgPnL: number
  winRate: number
}

function analyzeBestSetups(trades: any[]): SetupGroupResult[] {
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

function generateInsights(results: SetupGroupResult[]): string[] {
  if (!results.length) return []

  const insights: string[] = []

  const bestSession = results.find((r) => r.type === "session")
  const bestTicker = results.find((r) => r.type === "ticker")
  const bestDirection = results.find((r) => r.type === "direction")

  const formatMoney = (v: number) =>
    v < 0
      ? `-$${Math.abs(v).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
      : `$${v.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

  const formatPct = (v: number) => `${(v * 100).toFixed(0)}%`

  if (bestSession && bestSession.value !== "—") {
    insights.push(
      `You perform best trading ${bestSession.value} session (${formatMoney(
        bestSession.avgPnL
      )} avg, ${formatPct(bestSession.winRate)} win rate)`
    )
  }

  if (bestTicker && bestTicker.value !== "—") {
    insights.push(
      `${bestTicker.value} is your most profitable market (${formatMoney(
        bestTicker.avgPnL
      )} avg per trade)`
    )
  }

  if (bestDirection && bestDirection.value !== "—") {
    insights.push(
      `You are more profitable going ${bestDirection.value} (${formatMoney(
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

function analyzeCombinedSetups(trades: any[]): CombinedSetupResult[] {
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

  const formatMoney = (v: number) =>
    v < 0
      ? `-$${Math.abs(v).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
      : `$${v.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

  const formatPct = (v: number) => `${(v * 100).toFixed(0)}%`

  const best = meaningful[0]

  return [
    `Your strongest setup is trading ${formatCombo(
      best.key
    )} (${formatMoney(best.avgPnL)} avg, ${formatPct(
      best.winRate
    )} win rate over ${best.trades} trades)`,
  ]
}

function generateWorstInsight(worst: CombinedSetupResult | undefined): string | null {
  if (!worst) return null

  const formatMoney = (v: number) =>
    v < 0
      ? `-$${Math.abs(v).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
      : `$${v.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

  const formatPct = (v: number) => `${(v * 100).toFixed(0)}%`

  return `You struggle most trading ${formatCombo(
    worst.key
  )} (${formatMoney(worst.avgPnL)} avg, ${formatPct(
    worst.winRate
  )} win rate over ${worst.trades} trades)`
}

function detectLossStreak(trades: any[]): number | null {
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

function detectRRThreshold(trades: any[]): string | null {
  const lowRR = trades.filter((t) => {
    const r = Number(t.rr)
    return Number.isFinite(r) && r < 1
  })
  const highRR = trades.filter((t) => {
    const r = Number(t.rr)
    return Number.isFinite(r) && r >= 1
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

function formatMoney(v: number) {
  return v < 0
    ? `-$${Math.abs(v).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
    : `$${v.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
}

function calculateExpectancy(trades: any[]) {
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

function calculateStreaks(trades: any[]) {
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

type TradingHoursSummary = {
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

function analyzeTradingHours(trades: any[]): TradingHoursSummary | null {
  if (!trades || trades.length === 0) return null

  const hourlyMap: Record<number, number> = {}

  trades.forEach((trade) => {
    const timeSource = trade.entry_time || trade.exit_time
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

export default function Dashboard() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const {
    progress: gettingStartedProgress,
    signals: checklistSignals,
    signalsReady,
    refreshChecklistSignals,
  } = useGettingStartedProgress()
  const {
    user,
    profile,
    loading: profileLoading,
    setProfile,
    refreshProfile,
  } = useUserProfile()
  const [trades, setTrades] = useState<any[]>([])
  const [accountFilter, setAccountFilter] = useState("all")
  const [accountTypeFilter, setAccountTypeFilter] = useState("all")
  const [timeFilter, setTimeFilter] = useState("all")
  const [customRangeStart, setCustomRangeStart] = useState("")
  const [customRangeEnd, setCustomRangeEnd] = useState("")
  const [selectedDate, setSelectedDate] = useState("")
  const [showPublicOnly, setShowPublicOnly] = useState(false)
  const [loading, setLoading] = useState(true)
  const [showControls, setShowControls] = useState(false)
  const [showEquity, setShowEquity] = useState(true)
  const [showDrawdown, setShowDrawdown] = useState(true)
  const [showInsights, setShowInsights] = useState(true)
  const [showSessions, setShowSessions] = useState(true)
  const [showBestSetup, setShowBestSetup] = useState(true)
  const [showWorstSetup, setShowWorstSetup] = useState(true)
  const [showWarnings, setShowWarnings] = useState(true)
  /** Snapshot of gear-panel fields while open; committed on Save. */
  const [gearDraft, setGearDraft] = useState<GearDraftState | null>(null)
  const [ddInputFocused, setDdInputFocused] = useState(false)
  const [savingGearSettings, setSavingGearSettings] = useState(false)
  const [showPerformanceShare, setShowPerformanceShare] = useState(false)
  const [showImportModal, setShowImportModal] = useState(false)
  const didHydrateDashboardPrefs = useRef(false)
  /** Same fetch as /trades — used only for filter dropdown labels (#account_number vs UUID). */
  const [accountRows, setAccountRows] = useState<any[]>([])

  const accountById = useMemo(() => {
    const m: Record<string, any> = {}
    accountRows.forEach((acc) => {
      m[String(acc.id)] = acc
    })
    return m
  }, [accountRows])

  const tradesExcludingBacktest = useMemo(
    () => excludeBacktestTrades(trades),
    [trades]
  )

  function handleDashboardTimeframeChange(value: string) {
    setTimeFilter(value)
    if (value !== "custom") {
      setCustomRangeStart("")
      setCustomRangeEnd("")
    }
  }

  function handleDashboardCustomRangeApply(start: string, end: string) {
    setSelectedDate("")
    setCustomRangeStart(start)
    setCustomRangeEnd(end)
    setTimeFilter("custom")
  }

  const tradesForPerformanceSharePool = useMemo(
    () =>
      filterTradesForPerformanceSharePool(tradesExcludingBacktest, {
        selectedDate,
        accountFilter,
        accountTypeFilter,
        showPublicOnly,
      }),
    [
      tradesExcludingBacktest,
      selectedDate,
      accountFilter,
      accountTypeFilter,
      showPublicOnly,
    ]
  )

  // 🔥 SAFE DATA FETCH (FIXES YOUR ERROR)
  const refreshDashboardData = useCallback(async () => {
    setLoading(true)

    const currentUser = user
    if (!currentUser?.id) {
      setLoading(false)
      return
    }

    const { data: accountsData } = await supabase
      .from("accounts")
      .select("id, account_number, name, account_size, mode, category, is_active")
      .eq("user_id", currentUser.id)
    setAccountRows(accountsData || [])

    const { data: trades } = await supabase
      .from("trades")
      .select(
        "id, created_at, date, pnl, rr, entry_time, exit_time, account_name, account_size, account_id, mode, account_type, session, ticker, direction, strategy, trade_type, is_public, public_description"
      )
      .eq("user_id", currentUser.id)
      .order("date", { ascending: false })

    if (trades) setTrades(trades)

    dispatchGettingStartedSignalsRefresh()

    setLoading(false)
  }, [user])

  useEffect(() => {
    if (profileLoading) return
    if (!user?.id) {
      setLoading(false)
      return
    }
    void refreshDashboardData()
  }, [profileLoading, user?.id, refreshDashboardData])

  useEffect(() => {
    if (typeof window === "undefined") return
    const params = new URLSearchParams(window.location.search)
    if (params.get("checkout") !== "success") return
    void refreshDashboardData()
  }, [refreshDashboardData])

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      const node = e.target
      const el = node instanceof Element ? node : (node as Node).parentElement
      if (!el?.closest(".dashboard-controls")) {
        setShowControls(false)
      }
    }
    document.addEventListener("click", handleClick)
    return () => document.removeEventListener("click", handleClick)
  }, [])

  useEffect(() => {
    if (!showControls) {
      setGearDraft(null)
      setDdInputFocused(false)
      return
    }
    const raw = profile?.max_drawdown_limit
    setGearDraft({
      timeFilter,
      accountFilter,
      accountTypeFilter,
      showPublicOnly,
      showEquity,
      showDrawdown,
      showInsights,
      showSessions,
      showBestSetup,
      showWorstSetup,
      showWarnings,
      drawdownLimit:
        raw != null && raw !== "" ? sanitizeDrawdownLimitInput(String(raw)) : "",
    })
    // Snapshot when the panel opens only (avoid resetting drafts while editing).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showControls])

  useEffect(() => {
    if (loading || didHydrateDashboardPrefs.current) return
    didHydrateDashboardPrefs.current = true
    const p = loadDashboardGearPrefs()
    if (!p) return

    const {
      timeFilter: hydratedTimeFilter,
      accountFilter: hydratedAccountFilter,
      accountTypeFilter: hydratedAccountTypeFilter,
    } = sanitizeHydratedDashboardFilters({ prefs: p, trades: tradesExcludingBacktest })

    setTimeFilter(hydratedTimeFilter)
    setAccountFilter(hydratedAccountFilter)
    setAccountTypeFilter(hydratedAccountTypeFilter)

    const filtersChanged =
      hydratedTimeFilter !== p.timeFilter ||
      hydratedAccountFilter !== p.accountFilter ||
      hydratedAccountTypeFilter !== p.accountTypeFilter

    if (typeof p.showPublicOnly === "boolean") setShowPublicOnly(p.showPublicOnly)
    if (typeof p.showEquity === "boolean") setShowEquity(p.showEquity)
    if (typeof p.showDrawdown === "boolean") setShowDrawdown(p.showDrawdown)
    if (typeof p.showInsights === "boolean") setShowInsights(p.showInsights)
    if (typeof p.showSessions === "boolean") setShowSessions(p.showSessions)
    if (typeof p.showBestSetup === "boolean") setShowBestSetup(p.showBestSetup)
    if (typeof p.showWorstSetup === "boolean") setShowWorstSetup(p.showWorstSetup)
    if (typeof p.showWarnings === "boolean") setShowWarnings(p.showWarnings)

    if (filtersChanged) {
      saveDashboardGearPrefs({
        timeFilter: hydratedTimeFilter,
        accountFilter: hydratedAccountFilter,
        accountTypeFilter: hydratedAccountTypeFilter,
        showPublicOnly:
          typeof p.showPublicOnly === "boolean" ? p.showPublicOnly : false,
        showEquity: typeof p.showEquity === "boolean" ? p.showEquity : true,
        showDrawdown: typeof p.showDrawdown === "boolean" ? p.showDrawdown : true,
        showInsights: typeof p.showInsights === "boolean" ? p.showInsights : true,
        showSessions: typeof p.showSessions === "boolean" ? p.showSessions : true,
        showBestSetup: typeof p.showBestSetup === "boolean" ? p.showBestSetup : true,
        showWorstSetup: typeof p.showWorstSetup === "boolean" ? p.showWorstSetup : true,
        showWarnings: typeof p.showWarnings === "boolean" ? p.showWarnings : true,
      })
    }
  }, [loading, tradesExcludingBacktest])

  function formatNumber(value: number) {
    if (value === null || value === undefined) return "-"
    return value.toLocaleString()
  }

  // 🔥 MEMOIZED CALCULATIONS (PERFORMANCE BOOST)
  const {
    filteredTrades,
    accounts,
    totalTrades,
    winRate,
    totalPnL,
    avgRR,
    biggestLoss,
    bestTrade,
    maxStreak,
    sessionStats,
    avgWin,
    avgLoss,
    bestDay,
    worstDay,
    symbolStats,
    symbolPerformanceRows,
    strategyPerformanceRows,
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
  } = useMemo(() => {
    if (process.env.NODE_ENV === "development") {
      console.log("Trades:", tradesExcludingBacktest)
      if (tradesExcludingBacktest.length)
        console.log("Sample trade:", tradesExcludingBacktest[0])
    }

    const accountMap = new Map<
      string,
      { value: string; label: string; accountType?: string | null }
    >()
    tradesExcludingBacktest
      .filter(t => t.account_name && t.account_size && t.account_id)
      .forEach((t) => {
        const accountName = String(t.account_name || "").trim()
        const size = String(t.account_size || "").trim()
        const id = String(t.account_id || "").trim()
        const accRow = accountById[id]
        if (accRow?.is_active === false) return
        const value = `${accountName}|${size}|${id}`
        const num = accRow?.account_number
        const label = [accountName, size, num ? `• #${num}` : ""]
          .filter((x) => x !== "")
          .join(" ")
          .replace(/\s+/g, " ")
          .trim()
        if (!accountMap.has(value)) {
          accountMap.set(value, {
            value,
            label,
            accountType: t.mode ?? t.account_type,
          })
        }
      })
    const accounts = Array.from(accountMap.values())
    console.log("Accounts:", accounts)

    function filterByTime(trade: any) {
      if (timeFilter === "all") return true
      const now = new Date()
      const tradeDateRaw = trade.entry_time || trade.exit_time || trade.created_at
      if (!tradeDateRaw) return false
      const tradeDate = new Date(tradeDateRaw)
      if (timeFilter === "daily") {
        return tradeDate.toDateString() === now.toDateString()
      }
      if (timeFilter === "weekly") {
        const weekAgo = new Date()
        weekAgo.setDate(now.getDate() - 7)
        return tradeDate >= weekAgo
      }
      if (timeFilter === "monthly") {
        return (
          tradeDate.getMonth() === now.getMonth() &&
          tradeDate.getFullYear() === now.getFullYear()
        )
      }
      if (timeFilter === "yearly") {
        return tradeDate.getFullYear() === now.getFullYear()
      }
      if (timeFilter === "custom") {
        if (!customRangeStart?.trim() || !customRangeEnd?.trim()) return true
        const start = new Date(customRangeStart + "T00:00:00")
        const end = new Date(customRangeEnd + "T23:59:59.999")
        return tradeDate >= start && tradeDate <= end
      }
      return true
    }

    /** Public trades: DB flag and/or non-empty public note (matches InputTradeForm / feed). */
    function tradeIsPublic(t: any) {
      if (t?.is_public === true) return true
      const desc = t?.public_description
      return typeof desc === "string" && desc.trim().length > 0
    }

    const withoutPublicFilter = tradesExcludingBacktest.filter((trade) => {
      if (selectedDate) {
        const tradeDate = new Date(trade.created_at)
        const selected = new Date(selectedDate + "T00:00:00")
        if (
          tradeDate.getFullYear() !== selected.getFullYear() ||
          tradeDate.getMonth() !== selected.getMonth() ||
          tradeDate.getDate() !== selected.getDate()
        ) {
          return false
        }
      }

      if (!filterByTime(trade)) return false

      if (accountFilter !== "all") {
        const accountName = String(trade.account_name || "").trim()
        const size = String(trade.account_size || "").trim()
        const id = String(trade.account_id || "").trim()
        const accountKey = `${accountName}|${size}|${id}`
        if (accountKey !== accountFilter) return false
      }

      const tradeAcct = String(trade.mode ?? trade.account_type ?? "")
        .toLowerCase()
        .trim()
      const selectedAcct = accountTypeFilter.toLowerCase().trim()
      if (accountTypeFilter !== "all") {
        console.log("Filtering:", trade.account_type, accountTypeFilter)
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

    filteredTrades = filteredTrades.sort(
      (a, b) =>
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    )

    const totalTrades = filteredTrades.length
    const wins = filteredTrades.filter(t => t.pnl > 0)
    const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
    const totalPnL = filteredTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)

    const avgRR =
      filteredTrades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
      (filteredTrades.length || 1)

    const losses = filteredTrades
  .map(t => Number(t.pnl) || 0)
  .filter(p => p < 0)

const biggestLoss = losses.length > 0
  ? Math.min(...losses)
  : 0

    const bestTrade = filteredTrades.length
      ? Math.max(...filteredTrades.map((t) => Number(t.pnl) || 0))
      : 0

    let currentStreak = 0
    let maxStreak = 0
    filteredTrades.forEach(t => {
      if (t.pnl < 0) {
        currentStreak++
        if (currentStreak > maxStreak) maxStreak = currentStreak
      } else {
        currentStreak = 0
      }
    })

    const sessionStats: any = {}
    filteredTrades.forEach(t => {
      if (!sessionStats[t.session]) {
        sessionStats[t.session] = { pnl: 0, trades: 0, wins: 0 }
      }
      sessionStats[t.session].pnl += t.pnl || 0
      sessionStats[t.session].trades += 1
      if (t.pnl > 0) sessionStats[t.session].wins += 1
    })

    const symbolStats: Record<string, any> = {}

    filteredTrades.forEach((t) => {
      if (!symbolStats[t.ticker]) {
        symbolStats[t.ticker] = {
          pnl: 0,
          trades: 0,
          wins: 0
        }
      }

      symbolStats[t.ticker].pnl += t.pnl || 0
      symbolStats[t.ticker].trades += 1
      if (t.pnl > 0) symbolStats[t.ticker].wins += 1
    })

    let insightBestSymbol: string | null = null
    let insightBestSymbolAvg = -Infinity
    Object.entries(symbolStats).forEach(([symbol, data]: [string, any]) => {
      if (!symbol || symbol === "undefined" || data.trades < 3) return
      const avg = Number(data.pnl) / data.trades
      if (avg > insightBestSymbolAvg) {
        insightBestSymbolAvg = avg
        insightBestSymbol = symbol
      }
    })

    const tickerAgg: Record<string, { totalPnL: number; wins: number; totalTrades: number; rrSum: number }> = {}

    filteredTrades.forEach((t) => {
      const ticker = t.ticker || "—"
      if (!tickerAgg[ticker]) {
        tickerAgg[ticker] = { totalPnL: 0, wins: 0, totalTrades: 0, rrSum: 0 }
      }
      tickerAgg[ticker].totalPnL += t.pnl || 0
      tickerAgg[ticker].totalTrades += 1
      if (t.pnl > 0) tickerAgg[ticker].wins += 1
      tickerAgg[ticker].rrSum += Number(t.rr) || 0
    })

    const symbolPerformanceRows = Object.entries(tickerAgg)
      .map(([ticker, s]) => ({
        ticker,
        totalTrades: s.totalTrades,
        wins: s.wins,
        winRate: s.totalTrades ? (s.wins / s.totalTrades) * 100 : 0,
        totalPnL: s.totalPnL,
        avgRR: s.rrSum / (s.totalTrades || 1)
      }))
      .sort((a, b) => b.totalPnL - a.totalPnL)

    const strategyAgg: Record<
      string,
      { totalPnL: number; wins: number; totalTrades: number; rrSum: number }
    > = {}

    filteredTrades.forEach((t) => {
      const strategy = (t.strategy && String(t.strategy).trim()) || ""
      if (!strategy) return
      if (!strategyAgg[strategy]) {
        strategyAgg[strategy] = { totalPnL: 0, wins: 0, totalTrades: 0, rrSum: 0 }
      }
      strategyAgg[strategy].totalPnL += t.pnl || 0
      strategyAgg[strategy].totalTrades += 1
      if (t.pnl > 0) strategyAgg[strategy].wins += 1
      strategyAgg[strategy].rrSum += Number(t.rr) || 0
    })

    const strategyPerformanceRows = Object.entries(strategyAgg)
      .map(([strategy, s]) => ({
        strategy,
        totalTrades: s.totalTrades,
        wins: s.wins,
        winRate: s.totalTrades ? (s.wins / s.totalTrades) * 100 : 0,
        totalPnL: s.totalPnL,
        avgRR: s.rrSum / (s.totalTrades || 1),
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
      sessionBuckets[b].totalPnL += t.pnl || 0
      if (t.pnl > 0) sessionBuckets[b].wins += 1
    })

    const sessionPieData = [
      { name: "London", value: sessionBuckets.London.totalTrades },
      { name: "NY", value: sessionBuckets.NY.totalTrades },
      { name: "Asia", value: sessionBuckets.Asia.totalTrades }
    ]

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
      const resolved = resolveTradingTimeSourceForKey(t)
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
      const resolved = resolveTradingTimeSourceForKey(trade)
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

    const setupAgg: Record<string, { trades: number; wins: number; totalPnL: number }> = {}
    filteredTrades.forEach((t) => {
      const ty = (t.trade_type && String(t.trade_type).trim()) || ""
      if (!ty) return
      if (!setupAgg[ty]) setupAgg[ty] = { trades: 0, wins: 0, totalPnL: 0 }
      setupAgg[ty].trades += 1
      setupAgg[ty].totalPnL += t.pnl || 0
      if (t.pnl > 0) setupAgg[ty].wins += 1
    })

    let bestSetup: {
      trade_type: string
      trades: number
      winRate: number
      totalPnL: number
    } | null = null

    for (const [trade_type, d] of Object.entries(setupAgg)) {
      if (d.trades < 3) continue
      if (!bestSetup || d.totalPnL > bestSetup.totalPnL) {
        bestSetup = {
          trade_type,
          trades: d.trades,
          winRate: (d.wins / d.trades) * 100,
          totalPnL: d.totalPnL
        }
      }
    }

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
      (a, b) =>
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    )
    const streakData = calculateStreaks(chronologicalTrades)
    const expectancyData = calculateExpectancy(filteredTrades)
    const hourData = analyzeTradingHours(filteredTrades)
    let runningEquity = 0
    const equityDrawdownChartData = chronologicalTrades.map((trade, index) => {
      runningEquity += Number(trade.pnl) || 0

      if (process.env.NODE_ENV === "development" && index < 5) {
        console.log({
          equity: runningEquity,
        })
      }

      return {
        date: trade.created_at,
        equity: runningEquity,
      }
    })
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
      const resolved = resolveTradingTimeSourceForKey(t)
      if (!resolved) return
      const dateKey = getTradingDayKey(resolved)
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

    const winsOnly = filteredTrades.filter(t => t.pnl > 0)
    const lossesOnly = filteredTrades.filter(t => t.pnl < 0)

    const avgWin =
      winsOnly.reduce((sum, t) => sum + t.pnl, 0) / (winsOnly.length || 1)

    const avgLoss =
      lossesOnly.reduce((sum, t) => sum + t.pnl, 0) / (lossesOnly.length || 1)

    const hasTradingDayTimeSource = filteredTrades.some(
      (t) => resolveTradingTimeSourceForKey(t) != null
    )

    if (process.env.NODE_ENV === "development") {
      console.log(
        filteredTrades.map((t) => ({
          pnl: t.pnl,
          session: getTradingSession(t.entry_time || t.exit_time),
        }))
      )
    }

    return {
      filteredTrades,
      accounts,
      totalTrades,
      winRate,
      totalPnL,
      avgRR,
      biggestLoss,
      bestTrade,
      maxStreak,
      sessionStats,
      avgWin,
      avgLoss,
      bestDay,
      worstDay,
      symbolStats,
      symbolPerformanceRows,
      strategyPerformanceRows,
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
    tradesExcludingBacktest,
    showPublicOnly,
    accountFilter,
    accountTypeFilter,
    timeFilter,
    selectedDate,
    customRangeStart,
    customRangeEnd,
    accountById,
  ])

  useEffect(() => {
    if (accountFilter === "all") return
    if (!accounts.some((a) => a.value === accountFilter)) {
      setAccountFilter("all")
    }
  }, [accounts, accountFilter])

  // 🔥 LOADING STATE (FIXES GLITCH)
  const isPro = isProActive(profile)

  const showFreePlanAccountBanner = useMemo(() => {
    if (isPro || !tradesExcludingBacktest.length) return false
    const keys = new Set(
      tradesExcludingBacktest.map((t) =>
        [
          String(t.account_type ?? "").toLowerCase().trim(),
          String(t.account_size ?? "").trim(),
          String(t.account_id ?? "").trim(),
        ].join("-")
      )
    )
    return keys.size >= 1
  }, [tradesExcludingBacktest, isPro])

  if (profileLoading || loading || (user?.id && !signalsReady)) {
    return <SkeletonDashboardPage />
  }

  const hasNoTrades = tradesExcludingBacktest.length === 0

  const showOnboardingSection =
    shouldShowGettingStartedChecklist(user?.id, {
      hasSeenOnboardingCompletePopup:
        checklistSignals.hasSeenOnboardingCompletePopup,
      allComplete: gettingStartedProgress.allComplete,
    })

  const gettingStartedSection =
    showOnboardingSection && user?.id ? (
      <div className="hidden md:block">
        <GettingStartedChecklist
          progress={gettingStartedProgress}
          userId={user.id}
          profileId={user.id ?? profile?.id}
          firstPrivateTradeId={checklistSignals.firstPrivateTradeId}
          onChecklistRefresh={() => void refreshChecklistSignals()}
        />
      </div>
    ) : null

  const currentStreak =
    streakData?.currentType === "loss"
      ? -Number(streakData.currentStreak || 0)
      : streakData?.currentType === "win"
        ? Number(streakData.currentStreak || 0)
        : 0

  const grossProfit = filteredTrades
    .filter((t) => (Number(t.pnl) || 0) > 0)
    .reduce((sum, t) => sum + (Number(t.pnl) || 0), 0)

  const grossLoss = filteredTrades
    .filter((t) => (Number(t.pnl) || 0) < 0)
    .reduce((sum, t) => sum + Math.abs(Number(t.pnl) || 0), 0)

  const profitFactor = grossLoss === 0 ? 0 : grossProfit / grossLoss

  const dailyMap: Record<string, number> = {}

  filteredTrades.forEach((t) => {
    const resolved = resolveTradingTimeSourceForKey(t)
    if (!resolved) return
    const date = getTradingDayKey(resolved)
    if (!date) return

    if (!dailyMap[date]) {
      dailyMap[date] = 0
    }

    dailyMap[date] += Number(t.pnl) || 0
  })

  const dailyValues = Object.values(dailyMap)

  const avgDay =
    dailyValues.length > 0
      ? dailyValues.reduce((a, b) => a + b, 0) / dailyValues.length
      : 0

  const greenDays = dailyValues.filter((v) => v > 0).length

  const consistency =
    dailyValues.length > 0
      ? (greenDays / dailyValues.length) * 100
      : 0

  async function saveDashboardGearPanel() {
    if (!user || !gearDraft) return

    const rawLimit = finalizeDrawdownLimitInput(gearDraft.drawdownLimit).trim()
    const n =
      rawLimit === "" || rawLimit === "."
        ? null
        : Number(finalizeDrawdownLimitInput(gearDraft.drawdownLimit))
    if (
      rawLimit !== "" &&
      rawLimit !== "." &&
      (n === null || !Number.isFinite(n) || n < 0)
    ) {
      alert(
        "Enter a valid non-negative dollar amount for drawdown limit, or leave blank to clear."
      )
      return
    }

    setSavingGearSettings(true)
    const { error } = await supabase
      .from("profiles")
      .update({ max_drawdown_limit: n })
      .eq("id", user.id)
    setSavingGearSettings(false)

    if (error) {
      alert(error.message)
      return
    }

    const { error: mirrorErr } = await mirrorAccountSettingsMaxDrawdownLimit(
      supabase,
      user.id,
      n
    )
    if (mirrorErr) {
      console.error("mirror account_settings.max_drawdown_limit:", mirrorErr)
    }

    const nextAccount = sanitizeDashboardAccountFilter(
      gearDraft.accountFilter,
      accounts
    )

    setTimeFilter(gearDraft.timeFilter)
    setAccountFilter(nextAccount)
    setAccountTypeFilter(gearDraft.accountTypeFilter)
    setShowPublicOnly(gearDraft.showPublicOnly)
    setShowEquity(gearDraft.showEquity)
    setShowDrawdown(gearDraft.showDrawdown)
    setShowInsights(gearDraft.showInsights)
    setShowSessions(gearDraft.showSessions)
    setShowBestSetup(gearDraft.showBestSetup)
    setShowWorstSetup(gearDraft.showWorstSetup)
    setShowWarnings(gearDraft.showWarnings)

    saveDashboardGearPrefs({
      timeFilter: gearDraft.timeFilter,
      accountFilter: nextAccount,
      accountTypeFilter: gearDraft.accountTypeFilter,
      showPublicOnly: gearDraft.showPublicOnly,
      showEquity: gearDraft.showEquity,
      showDrawdown: gearDraft.showDrawdown,
      showInsights: gearDraft.showInsights,
      showSessions: gearDraft.showSessions,
      showBestSetup: gearDraft.showBestSetup,
      showWorstSetup: gearDraft.showWorstSetup,
      showWarnings: gearDraft.showWarnings,
    })

    setProfile((p: any) => (p ? { ...p, max_drawdown_limit: n } : p))
    setShowControls(false)
  }

  function cancelDashboardGearPanel() {
    setShowControls(false)
  }

  const handleImportModalComplete = useCallback(async () => {
    setShowImportModal(false)
    notifyGettingStartedChecklistMaybeCompleted()
    dispatchGettingStartedSignalsRefresh()
    await refreshDashboardData()
  }, [refreshDashboardData])

  const recentTradesList = (filteredTrades || [])
    .slice()
    .sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )
    .slice(0, 5)

  const recentTradesSection = (
    <div className="h-full rounded-xl border border-white/10 bg-white/10 p-3 md:p-4">
      <h3 className="mb-2 text-xs md:text-sm text-gray-400">Recent Trades</h3>

      <div className="max-h-[28rem] space-y-3 overflow-y-auto pr-1">
        {recentTradesList.length === 0 ? (
          <EmptyState
            title="No recent trades"
            description="Your latest trades will appear here once you log activity."
            action={
              tradesExcludingBacktest.length === 0 ? (
                <Link
                  href="/app"
                  className="text-sm font-medium text-blue-300 hover:text-blue-200"
                >
                  Add Trade →
                </Link>
              ) : undefined
            }
            className="py-6"
          />
        ) : (
          recentTradesList.map((trade) => (
            <div
              key={trade.id}
              className="rounded-lg border border-white/10 bg-black/20 p-3 text-sm"
            >
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0 space-y-1">
                  <p className="truncate font-semibold text-white">
                    {trade.ticker}
                    {trade.direction ? (
                      <span className="font-normal text-gray-400">
                        {" "}
                        • {trade.direction}
                      </span>
                    ) : null}
                  </p>
                  <p
                    className={`font-medium tabular-nums ${
                      (Number(trade.pnl) || 0) >= 0
                        ? "text-green-400"
                        : "text-red-400"
                    }`}
                  >
                    {formatCurrency(Number(trade.pnl) || 0)}
                  </p>
                  <p className="text-xs text-gray-400">
                    RR{" "}
                    {trade.rr != null && trade.rr !== ""
                      ? formatRR(trade.rr)
                      : "—"}
                  </p>
                  <p className="text-xs text-gray-500">
                    {formatEST(String(trade.created_at ?? ""))}
                  </p>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-1">
                  {String(trade.mode ?? trade.account_type ?? "")
                    .toLowerCase()
                    .trim() === "backtest" ? (
                    <span className="rounded-md bg-blue-500/80 px-2 py-1 text-xs text-white">
                      Backtest
                    </span>
                  ) : null}
                  {trade.public_description ? (
                    <span className="rounded-md bg-green-500/20 px-2 py-1 text-xs text-green-400">
                      Posted
                    </span>
                  ) : (
                    <span className="rounded-md bg-gray-500/20 px-2 py-1 text-xs text-gray-400">
                      Private
                    </span>
                  )}
                </div>
              </div>
              {trade.public_description ? (
                <p className="mt-2 line-clamp-2 text-sm text-gray-300">
                  {trade.public_description}
                </p>
              ) : null}
              {trade.strategy ? (
                <p className="mt-1 text-xs text-gray-400">Strategy: {trade.strategy}</p>
              ) : null}
            </div>
          ))
        )}
      </div>
    </div>
  )

  const pnlByWeekdaySection = (
    <DashboardWeekdayChart data={weekdayData} totalTrades={totalTrades} />
  )

  const sessionPerformanceSection = (
    <DashboardSessionChart
      sessionPieData={sessionPieData}
      sessionBuckets={sessionBuckets}
      totalTrades={totalTrades}
    />
  )

  const mobileEquityChartSlot = (
    <DashboardEquityCurve
      variant="mobile"
      data={equityDrawdownChartData}
      totalTrades={totalTrades}
    />
  )

  const dashboardUserIsPro = isProActive(profile)

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />

      <PostSetupImportModal
        open={showImportModal}
        onComplete={() => void handleImportModalComplete()}
      />

      <div className="w-full text-white px-3 pb-3 pt-0 md:px-10 md:pb-10">

        <div className="relative z-50 mx-auto w-full max-w-[1600px] px-4 md:px-6">
          {!hasNoTrades ? (
            <DashboardFilters
              accounts={accounts}
              accountFilter={accountFilter}
              onAccountChange={setAccountFilter}
              accountTypeFilter={accountTypeFilter}
              onAccountTypeChange={setAccountTypeFilter}
              timeframe={timeFilter}
              onTimeframeChange={handleDashboardTimeframeChange}
              customRangeStart={customRangeStart}
              customRangeEnd={customRangeEnd}
              onCustomRangeApply={handleDashboardCustomRangeApply}
              selectedDate={selectedDate}
              onSelectedDateChange={setSelectedDate}
              showPublicOnly={showPublicOnly}
              onTogglePublicOnly={() => setShowPublicOnly(!showPublicOnly)}
              onOpenPerformanceShare={() => setShowPerformanceShare(true)}
              showControls={showControls}
              onToggleShowControls={() => setShowControls((prev) => !prev)}
              gearDraft={gearDraft}
              setGearDraft={setGearDraft}
              ddInputFocused={ddInputFocused}
              setDdInputFocused={setDdInputFocused}
              savingGearSettings={savingGearSettings}
              hasUser={Boolean(user)}
              onSaveGear={() => void saveDashboardGearPanel()}
              onCancelGear={cancelDashboardGearPanel}
              showShareControls={totalTrades > 0}
            />
          ) : null}
          <DashboardHeader
            isPro={isPro}
            showFreePlanAccountBanner={showFreePlanAccountBanner}
          />
        </div>

          <div className="relative z-0 mx-auto w-full max-w-[1600px] px-4 md:px-6 flex flex-col gap-6 md:gap-8 overflow-visible">

  {hasNoTrades ? (
    <>
      <div className="rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-md md:p-8">
        <h2 className="bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-2xl font-semibold text-transparent md:text-3xl">
          Welcome to TradeTraxs
        </h2>
        <p className="mt-3 text-base font-medium text-gray-100 md:text-lg">
          Track every trade.
          <br />
          Discover your edge.
          <br />
          Improve your performance.
        </p>
        <p className="mt-3 max-w-2xl text-sm text-gray-400 md:text-base">
          Get started by logging your first trade or importing your trading history.
        </p>
        <div className="mt-6 flex flex-wrap items-center gap-3">
          <Link
            href="/app"
            className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-600"
          >
            Add Trade
          </Link>
          <button
            type="button"
            onClick={() => setShowImportModal(true)}
            className="rounded-lg border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/15"
          >
            Import CSV
          </button>
        </div>
        <div className="mt-8 border-t border-white/10 pt-6">
          <p className="text-sm font-medium text-gray-300">
            After your first trade you&apos;ll unlock:
          </p>
          <ul className="mt-3 space-y-2 text-sm text-gray-400">
            <li>• Performance statistics</li>
            <li>• Equity curve tracking</li>
            <li>• Session &amp; weekday analysis</li>
            <li>• Symbol performance insights</li>
          </ul>
        </div>
      </div>
      {gettingStartedSection}
    </>
  ) : totalTrades === 0 ? (
    <>
      {gettingStartedSection}
      <EmptyState
        title="No trades match your filters"
        description="Try adjusting your account, mode, timeframe, or date filters to see your trades."
        className="rounded-xl border border-white/10 bg-white/5 py-12 backdrop-blur-md"
      />
    </>
  ) : (
    <>
      {gettingStartedSection}
  {/* TOP: STATS + CHART */}
  <div className="grid overflow-visible lg:grid-cols-3 gap-4 md:gap-6">

    {/* LEFT: STATS */}
    <DashboardStatsGrid
      totalTrades={totalTrades}
      winRate={winRate}
      avgRR={avgRR}
      totalPnL={totalPnL}
      avgWin={avgWin}
      bestTrade={bestTrade}
      avgLoss={avgLoss}
      biggestLoss={biggestLoss}
      bestDay={bestDay}
      worstDay={worstDay}
      showEquity={showEquity}
      mobileEquitySlot={mobileEquityChartSlot}
      mobileWeekdayPnlSlot={pnlByWeekdaySection}
      expectancyData={expectancyData}
      streakData={streakData}
      hourData={hourData}
      showSessions={showSessions}
      mobileSessionsSlot={sessionPerformanceSection}
    />

    {/* RIGHT: CHARTS */}
    <div className="space-y-4 md:space-y-6 overflow-visible lg:col-span-2">
      {showEquity ? (
        <DashboardEquityCurve
          variant="desktop"
          data={equityDrawdownChartData}
          profitFactor={profitFactor}
          currentStreak={currentStreak}
          avgDay={avgDay}
          consistency={consistency}
          totalTrades={totalTrades}
        />
      ) : null}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {showSessions ? (
          <>
            {recentTradesSection}
            <div className="hidden md:block">{sessionPerformanceSection}</div>
          </>
        ) : (
          <div className="lg:col-span-2">{recentTradesSection}</div>
        )}
      </div>
    </div>

  </div>

  {/* SYMBOL + P&L BY WEEKDAY */}
  <div className="grid grid-cols-1 gap-4 md:gap-6 lg:grid-cols-3 lg:items-stretch">

    <div className="h-full overflow-x-auto rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 lg:col-span-2">
      <h3 className="mb-2 text-xs md:text-sm text-gray-400">Symbol Performance</h3>

      {symbolPerformanceRows.length === 0 ? (
        <EmptyState
          title="Not Enough Data Yet"
          description="Add more trades to unlock detailed analytics."
          className="py-8"
        />
      ) : (
      <table className="w-full min-w-[520px] text-xs md:text-sm">
        <thead>
          <tr className="border-b border-white/10 text-gray-400">
            <th className="py-2 text-center">Ticker</th>
            <th className="py-2 text-center">Trades</th>
            <th className="py-2 text-center">Win %</th>
            <th className="py-2 text-center">Total P&L</th>
            <th className="py-2 text-center">Avg RR</th>
          </tr>
        </thead>
        <tbody>
          {symbolPerformanceRows.map((row) => (
            <tr key={row.ticker} className="border-b border-white/10 hover:bg-white/10">
              <td className="py-2 text-center">{row.ticker}</td>
              <td className="py-2 text-center">{formatNumber(row.totalTrades)}</td>
              <td className="py-2 text-center">{row.winRate.toFixed(1)}%</td>
              <td
                className={`py-2 text-center ${
                  row.totalPnL >= 0 ? "text-green-400" : "text-red-400"
                }`}
              >
                {formatCurrency(row.totalPnL)}
              </td>
              <td className="py-2 text-center">{formatRR(row.avgRR)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      )}
    </div>

    <div className="hidden md:block">{pnlByWeekdaySection}</div>

  </div>

          {(showInsights || showBestSetup) ? (
          <div className="grid grid-cols-1 gap-4 md:gap-6 md:grid-cols-2">
            {showInsights ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
                {dashboardUserIsPro ? (
                  <>
                <h3 className="mb-2 text-xs md:text-sm text-gray-400">Performance Insights</h3>
                <p className="mb-3 text-[11px] md:text-xs text-gray-500">
                  Data-driven highlights (min. 3 trades per session, symbol, or
                  direction). Respects current filters.
                </p>
                {totalTrades > 0 && !hasTradingDayTimeSource ? (
                  <p className="mb-3 text-[11px] md:text-xs text-amber-200/90">
                    Trading day stats use entry/exit times with a 6PM EST session
                    rollover. Add entry/exit times to unlock these insights.
                  </p>
                ) : null}
                {insights.length > 0 ||
                insightBestSymbol ||
                insightBestWeekday ? (
                  <div className="space-y-2">
                    {insights.map((text, i) => (
                      <p
                        key={`${i}-${text.slice(0, 24)}`}
                        className="text-xs md:text-sm text-gray-200"
                      >
                        • {text}
                      </p>
                    ))}
                    {insightBestSymbol ? (
                      <p className="text-xs md:text-sm text-blue-200">
                        {`• ${insightBestSymbol} is your most profitable symbol (${formatCurrency(insightBestSymbolAvg)} avg per trade)`}
                      </p>
                    ) : null}
                    {insightBestWeekday ? (
                      <p className="text-xs md:text-sm text-blue-200">
                        {`• You perform best on ${insightBestWeekday}s (${formatCurrency(insightBestWeekdayAvg)} avg)`}
                      </p>
                    ) : null}
                  </div>
                ) : (
                  <p className="text-xs md:text-sm text-gray-400">
                    Not enough sample size yet — need at least 3 trades in a session,
                    symbol, or direction bucket (with current filters).
                  </p>
                )}
                  </>
                ) : (
                  <LockedFeature title="Performance Insights" />
                )}
            </div>
            ) : null}

            {showBestSetup ? (
            <div
              className={`rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md ${!showInsights ? "md:col-span-2" : ""}`}
            >
              {dashboardUserIsPro ? (
                <>
              <h3 className="mb-2 text-xs md:text-sm text-gray-400">
                Best Performing Setup
              </h3>
              {bestSetup ? (
                <div className="space-y-2 text-xs md:text-sm text-gray-300">
                  <p>
                    <span className="text-gray-400">Setup:</span>{" "}
                    <span className="text-sm md:text-lg font-semibold text-white">{bestSetup.trade_type}</span>
                  </p>
                  <p>
                    <span className="text-gray-400">Win rate:</span>{" "}
                    <span className="text-sm md:text-lg font-semibold text-white">{bestSetup.winRate.toFixed(1)}%</span>
                  </p>
                  <p>
                    <span className="text-gray-400">Total P&amp;L:</span>{" "}
                    <span
                      className={`text-sm md:text-lg font-semibold tabular-nums ${
                        bestSetup.totalPnL >= 0 ? "text-green-400" : "text-red-400"
                      }`}
                    >
                      {formatCurrency(bestSetup.totalPnL)}
                    </span>
                  </p>
                  <p>
                    <span className="text-gray-400">Trades:</span>{" "}
                    <span className="text-sm md:text-lg font-semibold text-white">{bestSetup.trades}</span>
                  </p>
                </div>
              ) : (
                <p className="text-xs md:text-sm text-gray-400">
                  Need at least 3 trades with the same setup type (and non-empty
                  trade type) to rank setups.
                </p>
              )}
                </>
              ) : (
                <LockedFeature title="Best Performing Setup" />
              )}
            </div>
            ) : null}
          </div>
          ) : null}

          {(showInsights || showWorstSetup || showWarnings) ? (
          <div className="grid grid-cols-1 gap-4 md:gap-6 md:grid-cols-2">
            {showInsights ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
                {dashboardUserIsPro ? (
                  <>
                <h3 className="mb-2 text-xs md:text-sm text-gray-400">Advanced Edge</h3>
                <p className="mb-3 text-[11px] md:text-xs text-gray-500">
                  Strongest <span className="text-gray-400">combined</span> setup
                  (pairs or triples, min. 3 trades). Same filters as above.
                </p>
                {combinedInsights.length > 0 ? (
                  <div className="space-y-2">
                    {combinedInsights.map((text, i) => (
                      <p
                        key={`combo-${i}-${text.slice(0, 20)}`}
                        className="text-xs md:text-sm font-medium text-emerald-300"
                      >
                        ⭐ {text}
                      </p>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs md:text-sm text-gray-400">
                    No qualifying combined setup yet — need 3+ trades with consistent
                    session, symbol, and direction data.
                  </p>
                )}
                  </>
                ) : (
                  <LockedFeature title="Advanced Edge" />
                )}
            </div>
            ) : null}

            {showWorstSetup ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
              {dashboardUserIsPro ? (
                <>
              <h3 className="mb-2 text-xs md:text-sm text-gray-400">Risk Insights</h3>
              <p className="mb-3 text-[11px] md:text-xs text-gray-500">
                Lowest-performing combined setup (same 3+ trade rule as Advanced Edge).
              </p>
              {worstInsight ? (
                <p className="text-sm md:text-lg font-semibold text-red-400">⚠️ {worstInsight}</p>
              ) : (
                <p className="text-xs md:text-sm text-gray-400">
                  No combined setup to rank yet, or filters removed too much data.
                </p>
              )}
                </>
              ) : (
                <LockedFeature title="Risk Insights" />
              )}
            </div>
            ) : null}

            {showWarnings ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md md:col-span-2">
              {dashboardUserIsPro ? (
                <>
              <h3 className="mb-2 text-xs md:text-sm text-gray-400">Behavior Warnings</h3>
              <p className="mb-3 text-[11px] md:text-xs text-gray-500">
                Post–loss streak win rate (next 5 trades) and RR sample comparison.
              </p>
              {warnings.length > 0 ? (
                <div className="space-y-2">
                  {warnings.map((w, i) => (
                    <p key={`warn-${i}-${w.slice(0, 16)}`} className="text-xs md:text-sm text-yellow-300">
                      🚨 {w}
                    </p>
                  ))}
                </div>
              ) : (
                <p className="text-xs md:text-sm text-gray-400">
                  No behavioral flags for the current trade set.
                </p>
              )}
                </>
              ) : (
                <LockedFeature title="Behavior Warnings" />
              )}
            </div>
            ) : null}
          </div>
          ) : null}

    </>
  )}

          </div>
      </div>

      <PerformanceShareModal
        open={showPerformanceShare}
        onClose={() => setShowPerformanceShare(false)}
        tradePool={tradesForPerformanceSharePool}
        subtitle="Dashboard · respects account, mode, date & public filters"
        profile={profile}
      />
    </>
  )
}
