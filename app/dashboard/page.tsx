"use client"

import Navbar from "../components/Navbar"
import TradeFilterBar from "../components/TradeFilterBar"
import ProfileOnboarding, {
  ONBOARDING_FLAG,
  profileNeedsUsername,
} from "../components/ProfileOnboarding"
import PostSetupImportModal from "../components/PostSetupImportModal"
import PerformanceShareModal from "../components/PerformanceShareModal"
import { useEffect, useState, useMemo, useRef } from "react"
import { supabase } from "../../lib/supabaseClient"
import { isProActive } from "../../lib/subscription"
import { filterTradesForPerformanceSharePool } from "@/lib/performanceShare"
import { formatEST } from "@/lib/formatEST"
import { formatCurrency } from "@/lib/formatCurrency"
import {
  getTradingDayKey,
  getTradingSession,
  getTradingWeekday,
  resolveTradingTimeSourceForKey,
} from "@/lib/formatDate"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  CartesianGrid,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell
} from "recharts"

const DASHBOARD_GEAR_PREFS_KEY = "tradetrax_dashboard_prefs_v1"

type DashboardGearPersistedPrefs = {
  timeFilter: string
  accountFilter: string
  accountTypeFilter: string
  showPublicOnly: boolean
  showEquity: boolean
  showDrawdown: boolean
  showInsights: boolean
  showSessions: boolean
  showBestSetup: boolean
  showWorstSetup: boolean
  showWarnings: boolean
}

type GearDraftState = DashboardGearPersistedPrefs & { drawdownLimit: string }

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

/** Strip to digits + one dot; max 2 decimal places (internal value for save). */
function sanitizeDrawdownLimitInput(raw: string): string {
  let t = raw.replace(/[^0-9.]/g, "")
  const dot = t.indexOf(".")
  if (dot !== -1) {
    t = t.slice(0, dot + 1) + t.slice(dot + 1).replace(/\./g, "")
  }
  const [intPart = "", frac] = t.split(".")
  if (frac !== undefined) {
    return `${intPart}.${frac.slice(0, 2)}`
  }
  return intPart
}

function finalizeDrawdownLimitInput(raw: string): string {
  let t = sanitizeDrawdownLimitInput(raw)
  if (t.endsWith(".")) t = t.slice(0, -1)
  return t
}

function formatDrawdownLimitForDisplay(raw: string, focused: boolean): string {
  const s = sanitizeDrawdownLimitInput(raw)
  if (focused) return s
  if (s === "" || s === ".") return ""
  const n = Number(s)
  if (!Number.isFinite(n) || n < 0) return ""
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(n)
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

/** 0 → 12 AM, 13 → 1 PM (12-hour clock labels). */
function formatHour(h: number) {
  const suffix = h >= 12 ? "PM" : "AM"
  const hour12 = h % 12 || 12
  return `${hour12} ${suffix}`
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
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [showImportModal, setShowImportModal] = useState(false)
  const [trades, setTrades] = useState<any[]>([])
  const [accountFilter, setAccountFilter] = useState("all")
  const [accountTypeFilter, setAccountTypeFilter] = useState("all")
  const [timeFilter, setTimeFilter] = useState("all")
  const [customRangeStart, setCustomRangeStart] = useState("")
  const [customRangeEnd, setCustomRangeEnd] = useState("")
  const [selectedDate, setSelectedDate] = useState("")
  const [showPublicOnly, setShowPublicOnly] = useState(false)
  const [user, setUser] = useState<any>(null)
  const [profile, setProfile] = useState<any>(null)
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
      filterTradesForPerformanceSharePool(trades, {
        selectedDate,
        accountFilter,
        accountTypeFilter,
        showPublicOnly,
      }),
    [trades, selectedDate, accountFilter, accountTypeFilter, showPublicOnly]
  )

  // 🔥 SAFE DATA FETCH (FIXES YOUR ERROR)
  useEffect(() => {
    let mounted = true

    async function fetchData() {
      setLoading(true)

      // ✅ get session ONCE (fix lock error)
      const { data: sessionData } = await supabase.auth.getSession()
      const currentUser = sessionData?.session?.user

      if (!currentUser) {
        setLoading(false)
        return
      }

      if (!mounted) return
      setUser(currentUser)

      const { data: accountsData } = await supabase
        .from("accounts")
        .select("id, account_number, name, account_size, mode, category")
        .eq("user_id", currentUser.id)
      if (mounted) setAccountRows(accountsData || [])

      const { data: statsData } = await supabase
        .from("trades")
        .select("pnl, rr")
        .eq("user_id", currentUser.id);

      const totalPnL =
        statsData?.reduce((sum, t) => sum + (t.pnl || 0), 0) || 0;

      const totalTrades = statsData?.length || 0;

      const wins =
        statsData?.filter((t) => (t.pnl || 0) > 0).length || 0;

      const winRate =
        totalTrades > 0 ? (wins / totalTrades) * 100 : 0;

      const avgRR =
        statsData && statsData.length > 0
          ? statsData.reduce((sum, t) => sum + (t.rr || 0), 0) /
            statsData.length
          : 0;

      // ✅ fetch trades ONLY for this user (huge speed boost)
      const { data: trades } = await supabase
        .from("trades")
        .select("*")
        .eq("user_id", currentUser.id)
        .order("date", { ascending: false })

      if (mounted && trades) setTrades(trades)

      // ✅ fetch user settings/profile
      const { data: profileData } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", currentUser.id)
        .single()

      if (mounted && profileData) setProfile(profileData)

      setLoading(false)
    }

    fetchData()

    return () => {
      mounted = false
    }
  }, [])

  useEffect(() => {
    if (loading || !profile || !user) return
    let fromSignup = false
    try {
      fromSignup = sessionStorage.getItem(ONBOARDING_FLAG) === "1"
    } catch {
      /* ignore */
    }
    if (fromSignup || profileNeedsUsername(profile.username)) {
      setShowOnboarding(true)
    }
  }, [loading, profile, user])

  useEffect(() => {
    if (loading || !profile || !user) return
    if (showOnboarding) return
    if (profile.onboarding_completed !== false) {
      setShowImportModal(false)
      return
    }
    setShowImportModal(true)
  }, [loading, profile, user, showOnboarding])

  async function completeCsvOnboarding() {
    if (!user?.id) return
    const { error } = await supabase
      .from("profiles")
      .update({ onboarding_completed: true })
      .eq("id", user.id)
    if (error) console.error("completeCsvOnboarding:", error)
    setProfile((p: any) => (p ? { ...p, onboarding_completed: true } : p))
    setShowImportModal(false)
  }

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
    const tf = p.timeFilter
    if (tf === "all" || tf === "daily" || tf === "weekly" || tf === "monthly") {
      setTimeFilter(tf)
    }
    if (typeof p.accountFilter === "string") setAccountFilter(p.accountFilter)
    if (
      p.accountTypeFilter === "all" ||
      p.accountTypeFilter === "funded" ||
      p.accountTypeFilter === "eval" ||
      p.accountTypeFilter === "live"
    ) {
      setAccountTypeFilter(p.accountTypeFilter)
    }
    if (typeof p.showPublicOnly === "boolean") setShowPublicOnly(p.showPublicOnly)
    if (typeof p.showEquity === "boolean") setShowEquity(p.showEquity)
    if (typeof p.showDrawdown === "boolean") setShowDrawdown(p.showDrawdown)
    if (typeof p.showInsights === "boolean") setShowInsights(p.showInsights)
    if (typeof p.showSessions === "boolean") setShowSessions(p.showSessions)
    if (typeof p.showBestSetup === "boolean") setShowBestSetup(p.showBestSetup)
    if (typeof p.showWorstSetup === "boolean") setShowWorstSetup(p.showWorstSetup)
    if (typeof p.showWarnings === "boolean") setShowWarnings(p.showWarnings)
  }, [loading])

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
      console.log("Trades:", trades)
      if (trades.length) console.log("Sample trade:", trades[0])
    }

    const accountMap = new Map<
      string,
      { value: string; label: string; accountType?: string | null }
    >()
    trades
      .filter(t => t.account_name && t.account_size && t.account_id)
      .forEach((t) => {
        const accountName = String(t.account_name || "").trim()
        const size = String(t.account_size || "").trim()
        const id = String(t.account_id || "").trim()
        const value = `${accountName}|${size}|${id}`
        const accRow = accountById[id]
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

    const withoutPublicFilter = trades.filter((trade) => {
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
    trades,
    showPublicOnly,
    accountFilter,
    accountTypeFilter,
    timeFilter,
    selectedDate,
    customRangeStart,
    customRangeEnd,
    accountById,
  ])

  // 🔥 LOADING STATE (FIXES GLITCH)
  const isPro = isProActive(profile)

  const showFreePlanAccountBanner = useMemo(() => {
    if (isPro || !trades.length) return false
    const keys = new Set(
      trades
        .filter((t) => String(t.mode ?? "").toLowerCase() !== "backtest")
        .map((t) =>
          [
            String(t.account_type ?? "").toLowerCase().trim(),
            String(t.account_size ?? "").trim(),
            String(t.account_id ?? "").trim(),
          ].join("-")
        )
    )
    return keys.size >= 1
  }, [trades, isPro])

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="w-full flex items-center justify-center text-white">
          Loading Dashboard...
        </div>
      </>
    )
  }

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

  const sectionTitle = "text-xs md:text-sm text-gray-400 uppercase tracking-wide mb-2"

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

    let nextAccount = gearDraft.accountFilter
    if (nextAccount !== "all" && !accounts.some((a) => a.value === nextAccount)) {
      nextAccount = "all"
    }

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

  const recentTradesSection = (
    <div className="h-full rounded-xl border border-white/10 bg-white/10 p-3 md:p-4">
      <h3 className="mb-2 text-xs md:text-sm text-gray-400">Recent Trades</h3>

      <div className="max-h-[28rem] space-y-3 overflow-y-auto pr-1">
        {(filteredTrades || [])
          .slice()
          .sort(
            (a, b) =>
              new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
          )
          .slice(0, 5)
          .map((trade) => (
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
                      ? trade.rr
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
          ))}
      </div>
    </div>
  )

  const pnlByWeekdaySection = (
    <div className="flex min-h-[300px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
      <h2 className="mb-3 text-sm md:text-base font-semibold text-blue-300">
        P&amp;L by Weekday
      </h2>
      <div className="w-full overflow-hidden">
      <ResponsiveContainer width="100%" height={280}>
        <LineChart
          data={weekdayData}
          margin={{ top: 10, right: 20, left: 20, bottom: 20 }}
        >
          <CartesianGrid stroke="#334155" />
          <XAxis
            dataKey="day"
            stroke="#94a3b8"
            tick={{ fill: "#94a3b8", fontSize: 12 }}
          />
          <YAxis
            stroke="#94a3b8"
            tick={{ fill: "#94a3b8", fontSize: 12 }}
            tickFormatter={(value) =>
              Number(value) < 0
                ? `-$${Math.abs(Number(value)).toLocaleString()}`
                : `$${Number(value).toLocaleString()}`
            }
          />
          <Tooltip
            formatter={(value) =>
              Number(value) < 0
                ? `-$${Math.abs(Number(value)).toLocaleString(undefined, {
                    minimumFractionDigits: 2,
                  })}`
                : `$${Number(value).toLocaleString(undefined, {
                    minimumFractionDigits: 2,
                  })}`
            }
            labelFormatter={(label) => `${label}`}
          />
          <Line type="monotone" dataKey="pnl" stroke="#38bdf8" strokeWidth={2} dot={{ r: 4, fill: "#38bdf8" }} />
        </LineChart>
      </ResponsiveContainer>
      </div>
    </div>
  )

  const sessionPerformanceSection = (
    <div className="flex min-h-[300px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
      <h2 className="mb-3 text-sm md:text-base font-semibold text-blue-300">
        Session Performance
      </h2>
      <div className="flex flex-1 flex-col gap-4">
        <div className="flex min-h-[240px] flex-col">
          <p className="mb-2 text-xs md:text-sm text-gray-400">Trades by Session</p>
          <div className="min-h-0 flex-1 w-full overflow-hidden">
            <ResponsiveContainer width="100%" height={240}>
              <PieChart>
                <Pie
                  data={sessionPieData}
                  dataKey="value"
                  nameKey="name"
                  cx="50%"
                  cy="50%"
                  outerRadius={88}
                  label={({ name, value }) => `${name}: ${value}`}
                >
                  {sessionPieData.map((entry, index) => (
                    <Cell
                      key={`cell-${entry.name}`}
                      fill={["#60a5fa", "#34d399", "#c084fc"][index % 3]}
                    />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </div>
        <div className="flex flex-col">
          <p className="mb-2 text-xs md:text-sm text-gray-400">Session breakdown</p>
          <div className="grid grid-cols-3 gap-2 md:gap-3">
            {(["London", "NY", "Asia"] as const).map((name) => {
              const s = sessionBuckets[name]
              const wr = s.totalTrades ? (s.wins / s.totalTrades) * 100 : 0
              const titleColor =
                name === "London"
                  ? "text-blue-300"
                  : name === "NY"
                    ? "text-emerald-400"
                    : "text-purple-300"
              return (
                <div
                  key={name}
                  className="rounded-lg border border-white/10 bg-white/5 p-2 md:p-3 text-center text-xs md:text-sm"
                >
                  <p className={`mb-2 font-semibold ${titleColor}`}>{name}</p>
                  <p className="text-gray-300">
                    <span className="text-gray-400">Trades:</span>{" "}
                    {formatNumber(s.totalTrades)}
                  </p>
                  <p className="text-gray-300">
                    <span className="text-gray-400">Win rate:</span> {wr.toFixed(1)}%
                  </p>
                  <p
                    className={`mt-1 text-sm md:text-lg font-semibold tabular-nums ${
                      s.totalPnL >= 0 ? "text-green-400" : "text-red-400"
                    }`}
                  >
                    {formatCurrency(s.totalPnL)}
                  </p>
                </div>
              )
            })}
          </div>
        </div>
      </div>
    </div>
  )

  function renderDashboardFilterSettings() {
    return (
    <div className="relative z-[100] shrink-0 dashboard-controls">
      <button
        type="button"
        onClick={() => setShowControls((prev) => !prev)}
        className="flex items-center justify-center rounded-lg bg-[#1f2937] p-2 text-white transition hover:bg-[#1f2937]/90 md:bg-transparent md:hover:bg-white/10"
        aria-label="Dashboard controls"
        aria-expanded={showControls}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden
        >
          <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
          <circle cx="12" cy="12" r="3" />
        </svg>
      </button>

      {showControls ? (
        <div className="absolute right-0 top-full z-[100] mt-2 w-[min(22rem,calc(100vw-1.5rem))] max-h-[min(85vh,36rem)] overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a]/95 p-4 shadow-xl shadow-black/40 backdrop-blur-md">
          <p className="mb-3 border-b border-white/10 pb-2 text-sm font-semibold text-white">
            Dashboard preferences
          </p>

          {!gearDraft ? (
            <p className="text-xs text-gray-400">Loading…</p>
          ) : (
            <>
              

              <div className="mb-3 space-y-2 rounded-lg border border-white/10 bg-black/25 p-3">
                <p className={sectionTitle}>Display</p>
                <label className="flex cursor-pointer items-center justify-between gap-2 text-sm text-gray-200">
                  <span>Performance charts</span>
                  <input
                    type="checkbox"
                    className="accent-emerald-500"
                    checked={gearDraft.showEquity && gearDraft.showDrawdown}
                    onChange={(e) => {
                      const on = e.target.checked
                      setGearDraft((d) =>
                        d ? { ...d, showEquity: on, showDrawdown: on } : d
                      )
                    }}
                  />
                </label>
                <label className="flex cursor-pointer items-center justify-between gap-2 text-sm text-gray-200">
                  <span>Insights overview</span>
                  <input
                    type="checkbox"
                    className="accent-emerald-500"
                    checked={gearDraft.showInsights}
                    onChange={() =>
                      setGearDraft((d) =>
                        d ? { ...d, showInsights: !d.showInsights } : d
                      )
                    }
                  />
                </label>
                <label className="flex cursor-pointer items-center justify-between gap-2 text-sm text-gray-200">
                  <span>Session chart</span>
                  <input
                    type="checkbox"
                    className="accent-emerald-500"
                    checked={gearDraft.showSessions}
                    onChange={() =>
                      setGearDraft((d) =>
                        d ? { ...d, showSessions: !d.showSessions } : d
                      )
                    }
                  />
                </label>
                <label className="flex cursor-pointer items-center justify-between gap-2 text-sm text-gray-200">
                  <span>Setups & behavior tips</span>
                  <input
                    type="checkbox"
                    className="accent-emerald-500"
                    checked={
                      gearDraft.showBestSetup &&
                      gearDraft.showWorstSetup &&
                      gearDraft.showWarnings
                    }
                    onChange={(e) => {
                      const on = e.target.checked
                      setGearDraft((d) =>
                        d
                          ? {
                              ...d,
                              showBestSetup: on,
                              showWorstSetup: on,
                              showWarnings: on,
                            }
                          : d
                      )
                    }}
                  />
                </label>
              </div>

              <div className="mb-3 rounded-lg border border-white/10 bg-black/25 p-3">
                <p className={sectionTitle}>Risk</p>
                <p className="mt-1 text-[11px] leading-snug text-gray-400">
                  Max drawdown from equity peak. Leave blank for no limit.
                </p>
                <label htmlFor="dashboard-max-dd" className="sr-only">
                  Max drawdown limit
                </label>
                <input
                  id="dashboard-max-dd"
                  type="text"
                  inputMode="decimal"
                  autoComplete="off"
                  placeholder="$0"
                  disabled={!user}
                  value={formatDrawdownLimitForDisplay(
                    gearDraft.drawdownLimit,
                    ddInputFocused
                  )}
                  onFocus={() => setDdInputFocused(true)}
                  onBlur={() => {
                    setDdInputFocused(false)
                    setGearDraft((d) =>
                      d
                        ? {
                            ...d,
                            drawdownLimit: finalizeDrawdownLimitInput(d.drawdownLimit),
                          }
                        : d
                    )
                  }}
                  onChange={(e) => {
                    const next = sanitizeDrawdownLimitInput(e.target.value)
                    setGearDraft((d) => (d ? { ...d, drawdownLimit: next } : d))
                  }}
                  className="mt-2 w-full rounded-lg border border-white/10 bg-[#020617] px-3 py-2 text-sm text-white tabular-nums placeholder:text-gray-500 focus:border-blue-400/50 focus:outline-none focus:ring-1 focus:ring-blue-400/40 disabled:opacity-50"
                />
              </div>

              <div className="mt-1 border-t border-white/10 pt-3">
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation()
                      void saveDashboardGearPanel()
                    }}
                    disabled={savingGearSettings || !user}
                    className="flex-1 rounded-lg bg-gradient-to-r from-blue-500 to-emerald-600 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:from-blue-600 hover:to-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    {savingGearSettings ? "Saving…" : "Save"}
                  </button>
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation()
                      cancelDashboardGearPanel()
                    }}
                    disabled={savingGearSettings}
                    className="flex-1 rounded-lg border border-white/15 bg-white/5 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
                  >
                    Cancel
                  </button>
                </div>
                <p className="mt-2 text-center text-[10px] text-gray-500">
                  Save applies defaults, display options, and your drawdown limit.
                </p>
              </div>
            </>
          )}
        </div>
      ) : null}
    </div>
    )
  }

  return (
    <>
      <Navbar />

      {showOnboarding && user && profile ? (
        <ProfileOnboarding
          userId={user.id}
          initialUsername={profile.username}
          initialBio={profile.bio}
          initialTradingStyle={profile.trading_style}
          initialStartedTrading={profile.started_trading}
          initialAvatarUrl={profile.avatar_url}
          suppressPostSaveRedirect
          onComplete={(patch) => {
            setProfile((p: any) => (p ? { ...p, ...patch } : p))
            setShowOnboarding(false)
            setShowImportModal(true)
          }}
        />
      ) : null}

      <PostSetupImportModal
        open={showImportModal}
        onComplete={() => void completeCsvOnboarding()}
      />

      <div className="w-full text-white px-3 pb-3 pt-0 md:px-10 md:pb-10">

        <div className="relative z-50 mx-auto w-full max-w-[1600px] px-4 md:px-6">
          <TradeFilterBar
            className="mt-2.5 mb-0"
            mobileThreeRowLayout
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
            publicNextToModes={
              <button
                type="button"
                onClick={() => setShowPublicOnly(!showPublicOnly)}
                className={`h-[34px] w-full whitespace-nowrap rounded-md border px-4 py-2 text-sm md:h-[34px] md:w-auto md:px-2 md:py-1 md:text-xs md:hidden ${
                  showPublicOnly
                    ? "border-emerald-400 bg-emerald-500 text-white hover:bg-emerald-600"
                    : "border-white/10 bg-[#0f172a] text-white hover:bg-[#1e293b]"
                }`}
              >
                Public
              </button>
            }
            settingsNextToModes={
              <div className="md:hidden">{renderDashboardFilterSettings()}</div>
            }
            trailing={
              <>
                <button
                  type="button"
                  onClick={() => setShowPerformanceShare(true)}
                  className="inline-flex h-[34px] w-full items-center justify-center whitespace-nowrap rounded-md bg-white/10 px-4 py-2 text-sm text-white hover:bg-white/20 md:hidden"
                  title="Share performance"
                  aria-label="Share performance"
                >
                  📤 Share
                </button>
                <button
                  type="button"
                  onClick={() => setShowPublicOnly(!showPublicOnly)}
                  className={`hidden md:inline-flex shrink-0 whitespace-nowrap rounded-md px-3 py-2 text-sm ${
                    showPublicOnly
                      ? "bg-emerald-500 text-white hover:bg-emerald-600"
                      : "bg-white/10 text-white hover:bg-white/20"
                  }`}
                >
                  Public Trades
                </button>
                <button
                  type="button"
                  onClick={() => setShowPerformanceShare(true)}
                  className="hidden md:inline-flex h-[34px] shrink-0 items-center whitespace-nowrap rounded-md bg-white/10 px-3 py-1 text-sm text-white hover:bg-white/20"
                  title="Share performance"
                  aria-label="Share performance"
                >
                  📤 Share
                </button>
                

                <div className="hidden md:flex shrink-0 items-center justify-center">
                  {renderDashboardFilterSettings()}
                </div>
              </>
            }
          />

          <div className="mt-1 mb-2 text-left text-sm text-white/60">
            Plan:{" "}
            <span
              className={`font-medium ${
                isPro ? "text-green-400" : "text-gray-400"
              }`}
            >
              {isPro ? "Pro" : "Free"}
            </span>
          </div>

          {showFreePlanAccountBanner ? (
            <div className="mb-4 rounded border border-yellow-500/20 bg-yellow-500/10 p-3 md:p-4">
              <p className="text-xs md:text-sm text-yellow-300">
                Free plan: 1 account limit. Upgrade for unlimited accounts.
              </p>
            </div>
          ) : null}

        </div>

          <div className="relative z-0 mx-auto w-full max-w-[1600px] px-4 md:px-6 flex flex-col gap-6 md:gap-8 overflow-visible">

  {/* TOP: STATS + CHART */}
  <div className="grid overflow-visible lg:grid-cols-3 gap-4 md:gap-6">

    {/* LEFT: STATS */}
    <div className="flex flex-col gap-4 md:block md:space-y-4">
      <div className="grid grid-cols-2 gap-3 md:gap-3">
        <Stat title="Trades" value={formatNumber(totalTrades)} />
        <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />
        <Stat title="Avg RR" value={avgRR.toFixed(2)} />
        <Stat title="P&L" value={formatCurrency(totalPnL)} positive={totalPnL >= 0} />
        {showEquity ? (
          <div className="col-span-2 block md:hidden overflow-visible rounded-xl border border-white/10 bg-white/10 p-3 backdrop-blur-md">
            <h2 className="mb-3 text-sm font-semibold text-blue-300">Equity Curve</h2>
            <div className="h-[240px] w-full">
              <ResponsiveContainer width="100%" height={240}>
                <LineChart
                  data={equityDrawdownChartData}
                  margin={{ top: 10, right: 12, left: 12, bottom: 20 }}
                >
                  <CartesianGrid stroke="#334155" />
                  <XAxis
                    dataKey="date"
                    stroke="#94a3b8"
                    tick={{ fill: "#94a3b8", fontSize: 11 }}
                    tickFormatter={(value) => {
                      const d = new Date(String(value))
                      if (Number.isNaN(d.getTime())) return String(value).slice(0, 10)
                      return `${d.getMonth() + 1}/${d.getDate()}`
                    }}
                    interval="preserveStartEnd"
                    minTickGap={24}
                    angle={-25}
                    textAnchor="end"
                    height={48}
                  />
                  <YAxis
                    stroke="#94a3b8"
                    tick={{ fill: "#94a3b8", fontSize: 11 }}
                    tickFormatter={(value) =>
                      Number(value) < 0
                        ? `-$${Math.abs(Number(value)).toLocaleString(undefined, {
                            minimumFractionDigits: 0,
                            maximumFractionDigits: 0,
                          })}`
                        : `$${Number(value).toLocaleString(undefined, {
                            minimumFractionDigits: 0,
                            maximumFractionDigits: 0,
                          })}`
                    }
                  />
                  <Tooltip
                    formatter={(value) => {
                      const n = Number(value)
                      const formatted =
                        n < 0 ? `-$${Math.abs(n).toLocaleString()}` : `$${n.toLocaleString()}`
                      return [formatted, "Equity"]
                    }}
                    labelFormatter={(label) => {
                      const s = String(label)
                      return formatEST(s) || s
                    }}
                    contentStyle={{
                      backgroundColor: "#0f172a",
                      border: "1px solid rgba(255,255,255,0.1)",
                      borderRadius: "8px",
                    }}
                    labelStyle={{ color: "#94a3b8" }}
                  />
                  <Line
                    type="monotone"
                    dataKey="equity"
                    name="Equity"
                    stroke="#22c55e"
                    strokeWidth={2}
                    dot={false}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>
        ) : null}
        <div className="col-span-2 block md:hidden">{pnlByWeekdaySection}</div>
        <Stat title="Avg Win" value={formatCurrency(avgWin)} positive />
        <Stat
          title="Best Trade"
          value={formatCurrency(bestTrade)}
          positive={bestTrade >= 0}
        />
        <Stat title="Avg Loss" value={formatCurrency(avgLoss)} positive={false} />
        <Stat title="Big Loss" value={formatCurrency(biggestLoss)} positive={false} />
        
        
        
        <Stat title="Best Day" value={formatCurrency(bestDay)} positive />
        <Stat title="Worst Day" value={formatCurrency(worstDay)} positive={false} />
      </div>

      <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
        <h3 className="mb-2 text-xs md:text-sm text-gray-400">Expectancy</h3>

        {expectancyData ? (
          <>
            <p
              className={`text-sm md:text-lg font-semibold ${
                expectancyData.expectancy >= 0
                  ? "text-green-400"
                  : "text-red-400"
              }`}
            >
              {formatMoney(expectancyData.expectancy)}
            </p>

            
          </>
        ) : (
          <p className="text-gray-500 text-xs md:text-sm">No data</p>
        )}
      </div>

      <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
        <h3 className="mb-2 text-xs md:text-sm text-gray-400">Streaks</h3>

        {streakData ? (
          <>
            <p className="text-sm md:text-lg font-semibold text-white">
              Current: {streakData.currentStreak}{" "}
              <span
                className={
                  streakData.currentType === "win"
                    ? "text-green-400"
                    : streakData.currentType === "loss"
                    ? "text-red-400"
                    : "text-gray-400"
                }
              >
                {streakData.currentType}
              </span>
            </p>

            <div className="text-[11px] md:text-xs text-gray-400 mt-2 space-y-1">
              <p>Max Wins: {streakData.maxWinStreak}</p>
              <p>Max Losses: {streakData.maxLossStreak}</p>
            </div>
          </>
        ) : (
          <p className="text-gray-500 text-xs md:text-sm">No data</p>
        )}
      </div>

      <div className="block md:hidden">
        {showSessions ? sessionPerformanceSection : null}
      </div>

      <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
        <h3 className="mb-2 text-xs md:text-sm text-gray-400">Trading Hours</h3>

        {hourData === null ? (
          <p className="text-gray-500 text-xs md:text-sm">No data</p>
        ) : !hourData.hasValidTradingHoursData ? (
          <p className="text-white/60 text-sm">
            Add entry/exit times to unlock trading hour insights
          </p>
        ) : (
          <>
            <p className="text-green-400">
              {`Best: ${formatHour(hourData.bestHour!)} (${formatCurrency(hourData.hourlyMap[hourData.bestHour!])})`}
            </p>
            <p className="text-red-400">
              {`Worst: ${formatHour(hourData.worstHour!)} (${formatCurrency(hourData.hourlyMap[hourData.worstHour!])})`}
            </p>
          </>
        )}
      </div>
    </div>

    {/* RIGHT: CHARTS */}
    <div className="space-y-4 md:space-y-6 overflow-visible lg:col-span-2">
      {showEquity ? (
        <div className="hidden md:block overflow-visible rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
          <h2 className="text-sm md:text-base font-semibold mb-3 text-blue-300">
            Equity Curve
          </h2>

          <div className="w-full h-[300px]">
          <ResponsiveContainer width="100%" height={300}>
            <LineChart
              data={equityDrawdownChartData}
              margin={{ top: 10, right: 20, left: 20, bottom: 20 }}
            >
              <CartesianGrid stroke="#334155" />
              <XAxis
                dataKey="date"
                stroke="#94a3b8"
                tick={{ fill: "#94a3b8", fontSize: 12 }}
                tickFormatter={(value) => {
                  const d = new Date(String(value))
                  if (Number.isNaN(d.getTime())) return String(value).slice(0, 10)
                  return `${d.getMonth() + 1}/${d.getDate()}`
                }}
                interval="preserveStartEnd"
                minTickGap={24}
                angle={-25}
                textAnchor="end"
                height={48}
              />
              <YAxis
                stroke="#94a3b8"
                tick={{ fill: "#94a3b8", fontSize: 12 }}
                tickFormatter={(value) =>
                  Number(value) < 0
                    ? `-$${Math.abs(Number(value)).toLocaleString(undefined, {
                        minimumFractionDigits: 0,
                        maximumFractionDigits: 0,
                      })}`
                    : `$${Number(value).toLocaleString(undefined, {
                        minimumFractionDigits: 0,
                        maximumFractionDigits: 0,
                      })}`
                }
              />
              <Tooltip
                formatter={(value) => {
                  const n = Number(value)
                  const formatted =
                    n < 0
                      ? `-$${Math.abs(n).toLocaleString()}`
                      : `$${n.toLocaleString()}`
                  return [formatted, "Equity"]
                }}
                labelFormatter={(label) => {
                  const s = String(label)
                  return formatEST(s) || s
                }}
                contentStyle={{
                  backgroundColor: "#0f172a",
                  border: "1px solid rgba(255,255,255,0.1)",
                  borderRadius: "8px",
                }}
                labelStyle={{ color: "#94a3b8" }}
              />
              <Legend
                wrapperStyle={{ paddingTop: 8 }}
                formatter={(value) => (
                  <span className="text-gray-300 text-xs">{value}</span>
                )}
              />
              <Line
                type="monotone"
                dataKey="equity"
                name="Equity"
                stroke="#22c55e"
                strokeWidth={2}
                dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
          </div>

          <div className="flex flex-wrap gap-3 mt-4">
            <div
              className={`px-3 py-2 rounded-lg text-sm font-medium backdrop-blur-md transition-all duration-200 hover:scale-[1.03] ${
                profitFactor >= 1
                  ? "text-green-400 bg-green-500/10 border border-green-500/20"
                  : "text-red-400 bg-red-500/10 border border-red-500/20"
              }`}
            >
              Profit Factor: {profitFactor.toFixed(2)}
            </div>

            <div
              className={`px-3 py-2 rounded-lg text-sm font-medium backdrop-blur-md transition-all duration-200 hover:scale-[1.03] ${
                currentStreak > 0
                  ? "text-green-400 bg-green-500/10 border border-green-500/20"
                  : "text-red-400 bg-red-500/10 border border-red-500/20"
              }`}
            >
              Streak:{" "}
              {currentStreak > 0
                ? `${currentStreak} Wins`
                : `${Math.abs(currentStreak)} Losses`}
            </div>

            <div
              className={`px-3 py-2 rounded-lg text-sm font-medium backdrop-blur-md transition-all duration-200 hover:scale-[1.03] ${
                avgDay > 0
                  ? "text-green-400 bg-green-500/10 border border-green-500/20"
                  : avgDay < 0
                    ? "text-red-400 bg-red-500/10 border border-red-500/20"
                    : "text-gray-300 bg-white/10 border border-white/10"
              }`}
            >
              Avg Day: {formatCurrency(avgDay)}
            </div>

            <div
              className={`px-3 py-2 rounded-lg text-sm font-medium backdrop-blur-md transition-all duration-200 hover:scale-[1.03] ${
                consistency >= 60
                  ? "text-green-400 bg-green-500/10 border border-green-500/20"
                  : consistency >= 30
                    ? "text-yellow-400 bg-yellow-500/10 border border-yellow-500/20"
                    : "text-red-400 bg-red-500/10 border border-red-500/20"
              }`}
            >
              Consistency: {consistency.toFixed(0)}%
            </div>
          </div>
        </div>
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
              <td className="py-2 text-center">{row.avgRR.toFixed(2)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>

    <div className="hidden md:block">{pnlByWeekdaySection}</div>

  </div>

          {(showInsights || showBestSetup) ? (
          <div className="grid grid-cols-1 gap-4 md:gap-6 md:grid-cols-2">
            {showInsights ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
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
            </div>
            ) : null}

            {showBestSetup ? (
            <div
              className={`rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md ${!showInsights ? "md:col-span-2" : ""}`}
            >
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
            </div>
            ) : null}
          </div>
          ) : null}

          {(showInsights || showWorstSetup || showWarnings) ? (
          <div className="grid grid-cols-1 gap-4 md:gap-6 md:grid-cols-2">
            {showInsights ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
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
            </div>
            ) : null}

            {showWorstSetup ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
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
            </div>
            ) : null}

            {showWarnings ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md md:col-span-2">
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
            </div>
            ) : null}
          </div>
          ) : null}

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

function Stat({ title, value, positive }: any) {
  let color = "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"
  const displayValue =
    typeof value === "number"
      ? value.toLocaleString(undefined, {
          minimumFractionDigits: 0,
          maximumFractionDigits: 2,
        })
      : String(value ?? "")

  return (
    <div className="flex min-h-[90px] w-full flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-3 text-center backdrop-blur-md md:p-4">
      <p className="text-xs md:text-sm text-gray-400 mb-1">{title}</p>
      <div className="w-full text-center">
        <span
          className={`block font-semibold text-base md:text-lg lg:text-xl text-center leading-tight whitespace-nowrap tabular-nums ${color}`}
        >
          {displayValue}
        </span>
      </div>
    </div>
  )
}
