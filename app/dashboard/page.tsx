"use client"

import Link from "next/link"
import Navbar from "../components/Navbar"
import TradeFilterBar from "../components/TradeFilterBar"
import ProfileOnboarding, {
  ONBOARDING_FLAG,
  profileNeedsUsername,
} from "../components/ProfileOnboarding"
import { useEffect, useState, useMemo } from "react"
import { supabase } from "../../lib/supabaseClient"
import { isProActive } from "../../lib/subscription"
import ProGate from "../components/ProGate"
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

function formatHour(h: number) {
  const suffix = h >= 12 ? "PM" : "AM"
  const hour = h % 12 || 12
  return `${hour} ${suffix}`
}

function calculateDrawdown(trades: any[]) {
  let equity = 0
  let peak = 0
  let maxDrawdown = 0
  let currentDrawdown = 0
  let peakIndex = 0
  let recoveryIndex: number | null = null

  const equityCurve: { equity: number; peak: number; drawdown: number }[] = []

  trades.forEach((trade, i) => {
    equity += Number(trade.pnl) || 0

    if (equity > peak) {
      peak = equity
      peakIndex = i
    }

    const drawdown = peak - equity

    if (drawdown > maxDrawdown) {
      maxDrawdown = drawdown
      recoveryIndex = null
    }

    if (drawdown === 0 && recoveryIndex === null && i > peakIndex) {
      recoveryIndex = i
    }

    currentDrawdown = drawdown

    equityCurve.push({
      equity,
      peak,
      drawdown,
    })
  })

  const recoveryTrades =
    recoveryIndex !== null ? recoveryIndex - peakIndex : null

  const recoveryPercent =
    peak > 0 ? (maxDrawdown / peak) * 100 : 0

  return {
    maxDrawdown,
    currentDrawdown,
    recoveryTrades,
    recoveryPercent,
    equityCurve,
  }
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

type HourlyAnalysisRow = { hour: number; avgPnL: number; trades: number }

function analyzeTradingHours(trades: any[]) {
  if (!trades || trades.length === 0) return null

  const hourlyStats: Record<number, { totalPnL: number; trades: number }> = {}

  trades.forEach((trade) => {
    const raw = trade.created_at ?? trade.date
    if (!raw) return
    const date = new Date(raw)
    if (Number.isNaN(date.getTime())) return

    const hour = date.getHours()

    if (!hourlyStats[hour]) {
      hourlyStats[hour] = {
        totalPnL: 0,
        trades: 0,
      }
    }

    hourlyStats[hour].totalPnL += Number(trade.pnl) || 0
    hourlyStats[hour].trades += 1
  })

  const results: HourlyAnalysisRow[] = Object.entries(hourlyStats).map(
    ([hourStr, data]) => ({
      hour: Number(hourStr),
      avgPnL: data.totalPnL / data.trades,
      trades: data.trades,
    })
  )

  if (results.length === 0) return null

  results.sort((a, b) => b.avgPnL - a.avgPnL)

  return {
    best: results[0],
    worst: results[results.length - 1],
  }
}

export default function Dashboard() {
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [trades, setTrades] = useState<any[]>([])
  const [accountFilter, setAccountFilter] = useState("all")
  const [accountTypeFilter, setAccountTypeFilter] = useState("all")
  const [timeFilter, setTimeFilter] = useState("all")
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

      // ✅ fetch trades ONLY for this user (huge speed boost)
      const { data: tradesData } = await supabase
        .from("trades")
        .select("*")
        .eq("user_id", currentUser.id)

      if (mounted && tradesData) setTrades(tradesData)

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

  // 🔥 FORMATTERS
  function formatCurrency(value: number) {
    if (value === null || value === undefined) return "-"
    return `${value < 0 ? "-" : ""}$${Math.abs(value).toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

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
    maxStreak,
    sessionStats,
    avgWin,
    avgLoss,
    bestDay,
    worstDay,
    symbolStats,
    symbolPerformanceRows,
    sessionBuckets,
    bestSetup,
    insights,
    combinedInsights,
    worstInsight,
    warnings,
    drawdownData,
    equityDrawdownChartData,
    expectancyData,
    streakData,
    hourData,
    weekdayData,
    sessionPieData
  } = useMemo(() => {

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
        const label = `${accountName} ${size} #${id}`
          .trim()
          .replace(/\s+/g, " ")
        if (!accountMap.has(value)) {
          accountMap.set(value, { value, label, accountType: t.account_type })
        }
      })
    const accounts = Array.from(accountMap.values())
    console.log("Accounts:", accounts)

    function filterByTime(trade: any) {
      if (timeFilter === "all") return true
      const now = new Date()
      const tradeDate = new Date(trade.created_at)
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
      return true
    }

    const filteredTrades = trades
      .filter((trade) => {
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

        const tradeAcct = String(trade.account_type ?? "")
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
      .sort(
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

    const shortDayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const

    filteredTrades.forEach((t) => {
      const d = new Date(t.created_at)
      const short = shortDayNames[d.getDay()] as string
      if (short in weekdayMap) {
        weekdayMap[short as keyof typeof weekdayMap] += t.pnl || 0
      }
    })

    const weekdayData = (["Mon", "Tue", "Wed", "Thu", "Fri"] as const).map((day) => ({
      day,
      pnl: weekdayMap[day]
    }))

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
    const drawdownData = calculateDrawdown(chronologicalTrades)
    const expectancyData = calculateExpectancy(filteredTrades)
    const hourData = analyzeTradingHours(filteredTrades)
    const equityDrawdownChartData = chronologicalTrades.map((trade, i) => {
      const pt = drawdownData.equityCurve[i]
      return {
        date: trade.created_at,
        equity: pt?.equity ?? 0,
        drawdown: pt?.drawdown ?? 0,
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

    function toEST(date: Date) {
      return new Date(date.toLocaleString("en-US", { timeZone: "America/New_York" }))
    }

    function toESTDateString(date: Date) {
      return toEST(date).toISOString().split("T")[0]
    }

    const dailyMap: Record<string, number> = {}

    filteredTrades.forEach((t) => {
      const estDate = toESTDateString(new Date(t.created_at))
      dailyMap[estDate] = (dailyMap[estDate] || 0) + (t.pnl || 0)
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

    return {
      filteredTrades,
      accounts,
      totalTrades,
      winRate,
      totalPnL,
      avgRR,
      biggestLoss,
      maxStreak,
      sessionStats,
      avgWin,
      avgLoss,
      bestDay,
      worstDay,
      symbolStats,
      symbolPerformanceRows,
      sessionBuckets,
      bestSetup,
      insights,
      combinedInsights,
      worstInsight,
      warnings,
      drawdownData,
      equityDrawdownChartData,
      expectancyData,
      streakData,
      hourData,
      weekdayData,
      sessionPieData
    }

  }, [trades, accountFilter, accountTypeFilter, timeFilter, selectedDate])

  // 🔥 LOADING STATE (FIXES GLITCH)
  if (loading) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center text-white bg-black">
          Loading Dashboard...
        </div>
      </>
    )
  }

  const isPro = isProActive(profile)

  const drawdownLimitRaw = profile?.max_drawdown_limit
  const drawdownLimitCap =
    drawdownLimitRaw != null &&
    drawdownLimitRaw !== "" &&
    Number.isFinite(Number(drawdownLimitRaw)) &&
    Number(drawdownLimitRaw) > 0
      ? Number(drawdownLimitRaw)
      : null

  const drawdownLimitBreached =
    drawdownLimitCap != null &&
    (drawdownData.currentDrawdown >= drawdownLimitCap ||
      drawdownData.maxDrawdown >= drawdownLimitCap)

  const sectionTitle = "text-xs text-gray-400 uppercase tracking-wide mb-2"

  const recentTradesSection = (
    <div className="h-full rounded-xl border border-white/10 bg-white/10 p-4">
      <h3 className="mb-2 text-sm text-gray-400">Recent Trades</h3>

      <div className="max-h-[28rem] space-y-3 overflow-y-auto pr-1">
        {(filteredTrades || [])
          .slice()
          .sort(
            (a, b) =>
              new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
          )
          .filter((trade) =>
            showPublicOnly
              ? trade.public_description &&
                trade.public_description.length > 0
              : true
          )
          .slice(0, showPublicOnly ? 200 : 5)
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
                </div>
                <div className="flex shrink-0 flex-col items-end gap-1">
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
            </div>
          ))}
      </div>
    </div>
  )

  const pnlByWeekdaySection = (
    <div className="flex min-h-[300px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
      <h2 className="mb-3 text-base font-semibold text-blue-300">
        P&amp;L by Weekday
      </h2>
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
  )

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
          onComplete={(patch) => {
            setProfile((p: any) => (p ? { ...p, ...patch } : p))
            setShowOnboarding(false)
          }}
        />
      ) : null}

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-10">

        <div className="relative z-50 mx-auto max-w-6xl">
          <h1 className="mb-4 text-center text-2xl font-semibold text-blue-300">
            Dashboard
          </h1>

          <TradeFilterBar
            className="mb-8"
            accounts={accounts}
            accountFilter={accountFilter}
            onAccountChange={setAccountFilter}
            accountTypeFilter={accountTypeFilter}
            onAccountTypeChange={setAccountTypeFilter}
            timeframe={timeFilter}
            onTimeframeChange={setTimeFilter}
            selectedDate={selectedDate}
            onSelectedDateChange={setSelectedDate}
            trailing={
              <>
                <button
                  type="button"
                  onClick={() => setShowPublicOnly(!showPublicOnly)}
                  className={`shrink-0 whitespace-nowrap rounded-md px-3 py-1 text-sm ${
                    showPublicOnly
                      ? "bg-emerald-500 text-white hover:bg-emerald-600"
                      : "bg-white/10 text-white hover:bg-white/20"
                  }`}
                >
                  Public Trades
                </button>

                <div className="relative z-50 shrink-0 dashboard-controls">
                  <button
                    type="button"
                    onClick={() => setShowControls((prev) => !prev)}
                    className="rounded-lg p-2 text-white transition hover:bg-white/10"
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
              <div className="absolute right-0 top-full z-50 mt-2 w-72 rounded-lg border border-white/10 bg-[#0f172a] p-4 shadow-lg">
                <p className="text-sm font-semibold text-white mb-3 pb-2 border-b border-white/10">
                  Dashboard controls
                </p>

                <div className="mb-4">
                  <p className={sectionTitle}>Display</p>

                  <label className="flex justify-between items-center gap-3 text-sm mb-2 cursor-pointer">
                    <span>Equity Curve</span>
                    <input
                      type="checkbox"
                      className="accent-emerald-500"
                      checked={showEquity}
                      onChange={() => setShowEquity((v) => !v)}
                    />
                  </label>

                  <label className="flex justify-between items-center gap-3 text-sm mb-2 cursor-pointer">
                    <span>Drawdown</span>
                    <input
                      type="checkbox"
                      className="accent-emerald-500"
                      checked={showDrawdown}
                      onChange={() => setShowDrawdown((v) => !v)}
                    />
                  </label>

                  <label className="flex justify-between items-center gap-3 text-sm mb-2 cursor-pointer">
                    <span>Insights</span>
                    <input
                      type="checkbox"
                      className="accent-emerald-500"
                      checked={showInsights}
                      onChange={() => setShowInsights((v) => !v)}
                    />
                  </label>

                  <label className="flex justify-between items-center gap-3 text-sm cursor-pointer">
                    <span>Session Chart</span>
                    <input
                      type="checkbox"
                      className="accent-emerald-500"
                      checked={showSessions}
                      onChange={() => setShowSessions((v) => !v)}
                    />
                  </label>
                </div>

                <div className="mb-4 rounded-lg border border-white/10 bg-black/20 p-3">
                  <p className={sectionTitle}>Risk</p>
                  <p className="mt-2 text-xs text-gray-400">
                    Set your max drawdown limit under{" "}
                    <Link
                      href="/settings"
                      className="text-blue-300 underline hover:text-blue-200"
                    >
                      Settings → Profile
                    </Link>
                    .
                  </p>
                </div>

                <div className="mb-0">
                  <p className={sectionTitle}>Analytics</p>

                  <label className="flex justify-between items-center gap-3 text-sm mb-2 cursor-pointer">
                    <span>Show Best Setup</span>
                    <input
                      type="checkbox"
                      className="accent-emerald-500"
                      checked={showBestSetup}
                      onChange={() => setShowBestSetup((v) => !v)}
                    />
                  </label>

                  <label className="flex justify-between items-center gap-3 text-sm mb-2 cursor-pointer">
                    <span>Show Worst Setup</span>
                    <input
                      type="checkbox"
                      className="accent-emerald-500"
                      checked={showWorstSetup}
                      onChange={() => setShowWorstSetup((v) => !v)}
                    />
                  </label>

                  <label className="flex justify-between items-center gap-3 text-sm cursor-pointer">
                    <span>Behavior Warnings</span>
                    <input
                      type="checkbox"
                      className="accent-emerald-500"
                      checked={showWarnings}
                      onChange={() => setShowWarnings((v) => !v)}
                    />
                  </label>
                </div>
              </div>
                  ) : null}
                </div>
              </>
            }
          />

        </div>

        <ProGate isPro={isPro}>
          <div className="relative z-0 space-y-6 overflow-visible">

  {/* TOP: STATS + CHART */}
  <div className="grid overflow-visible lg:grid-cols-3 gap-6">

    {/* LEFT: STATS */}
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        <Stat title="Trades" value={formatNumber(totalTrades)} />
        <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />
        <Stat title="P&L" value={formatCurrency(totalPnL)} positive={totalPnL >= 0} />
        <Stat title="Avg RR" value={avgRR.toFixed(2)} />
        <Stat title="Big Loss" value={formatCurrency(biggestLoss)} positive={false} />
        <Stat title="Streak" value={maxStreak} />
        <Stat title="Avg Win" value={formatCurrency(avgWin)} positive />
        <Stat title="Avg Loss" value={formatCurrency(avgLoss)} positive={false} />
        <Stat title="Best Day" value={formatCurrency(bestDay)} positive />
        <Stat title="Worst Day" value={formatCurrency(worstDay)} positive={false} />
      </div>

      {showDrawdown ? (
        <div
          className={`rounded-xl border bg-white/10 p-4 backdrop-blur-md ${
            drawdownLimitBreached ? "border-amber-400/60" : "border-white/10"
          }`}
        >
          <h3 className="mb-2 text-sm text-gray-400">Drawdown</h3>

          <p className="text-lg font-semibold text-red-400">
            Max: {formatMoney(drawdownData.maxDrawdown)}
          </p>

          <p className="text-sm text-gray-300">
            Current: {formatMoney(drawdownData.currentDrawdown)}
          </p>

          {drawdownLimitCap == null ? (
            <p className="text-xs text-gray-500 mt-2">
              Limit: not set — configure in Settings.
            </p>
          ) : (
            <>
              <p className="text-sm text-gray-300 mt-2">
                Your limit: {formatMoney(drawdownLimitCap)}
              </p>
              {drawdownLimitBreached ? (
                <p className="text-xs text-amber-300 mt-1">
                  This range has met or exceeded your drawdown limit (current or historical
                  max).
                </p>
              ) : (
                <p className="text-xs text-gray-500 mt-1">Within your configured limit.</p>
              )}
            </>
          )}
        </div>
      ) : null}

      <div className="rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
        <h3 className="mb-2 text-sm text-gray-400">Expectancy</h3>

        {expectancyData ? (
          <>
            <p
              className={`text-lg font-semibold ${
                expectancyData.expectancy >= 0
                  ? "text-green-400"
                  : "text-red-400"
              }`}
            >
              {formatMoney(expectancyData.expectancy)}
            </p>

            <div className="text-xs text-gray-400 mt-2 space-y-1">
              <p>Win Rate: {(expectancyData.winRate * 100).toFixed(0)}%</p>
              <p>Avg Win: {formatMoney(expectancyData.avgWin)}</p>
              <p>Avg Loss: {formatMoney(expectancyData.avgLoss)}</p>
            </div>
          </>
        ) : (
          <p className="text-gray-500 text-sm">No data</p>
        )}
      </div>

      <div className="rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
        <h3 className="mb-2 text-sm text-gray-400">Streaks</h3>

        {streakData ? (
          <>
            <p className="text-lg font-semibold text-white">
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

            <div className="text-xs text-gray-400 mt-2 space-y-1">
              <p>Max Wins: {streakData.maxWinStreak}</p>
              <p>Max Losses: {streakData.maxLossStreak}</p>
            </div>
          </>
        ) : (
          <p className="text-gray-500 text-sm">No data</p>
        )}
      </div>

      <div className="rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
        <h3 className="mb-2 text-sm text-gray-400">Trading Hours</h3>

        {hourData ? (
          <>
            <p className="text-green-400 text-sm">
              Best: {formatHour(hourData.best.hour)} (
              {formatMoney(hourData.best.avgPnL)})
            </p>

            <p className="text-red-400 text-sm mt-1">
              Worst: {formatHour(hourData.worst.hour)} (
              {formatMoney(hourData.worst.avgPnL)})
            </p>
          </>
        ) : (
          <p className="text-gray-500 text-sm">No data</p>
        )}
      </div>
    </div>

    {/* RIGHT: CHARTS */}
    <div className="space-y-6 overflow-visible lg:col-span-2">
      {showEquity ? (
        <div className="overflow-visible rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
          <h2 className="text-base font-semibold mb-3 text-blue-300">
            Equity Curve
          </h2>

          <div className="overflow-visible">
          <ResponsiveContainer width="100%" height={350}>
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
                formatter={(value, name) => {
                  const n = Number(value)
                  const formatted =
                    n < 0
                      ? `-$${Math.abs(n).toLocaleString()}`
                      : `$${n.toLocaleString()}`
                  const label =
                    name === "Equity" || name === "equity"
                      ? "Equity"
                      : "Drawdown"
                  return [formatted, label]
                }}
                labelFormatter={(label) => {
                  const d = new Date(String(label))
                  if (Number.isNaN(d.getTime())) return String(label)
                  return d.toLocaleString(undefined, {
                    month: "short",
                    day: "numeric",
                    year: "numeric",
                    hour: "numeric",
                    minute: "2-digit",
                  })
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
              <Line
                type="monotone"
                dataKey="drawdown"
                name="Drawdown"
                stroke="#ef4444"
                strokeWidth={2}
                dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
          </div>

          <div className="mt-3 flex flex-wrap gap-4 text-sm">
            <div className="rounded-lg border border-white/10 bg-white/5 px-3 py-2">
              <span className="text-gray-400">Max DD:</span>{" "}
              <span className="text-red-400 font-medium">
                {formatMoney(drawdownData.maxDrawdown)}
              </span>
            </div>

            <div className="rounded-lg border border-white/10 bg-white/5 px-3 py-2">
              <span className="text-gray-400">Current DD:</span>{" "}
              <span className="text-yellow-300 font-medium">
                {formatMoney(drawdownData.currentDrawdown)}
              </span>
            </div>

            <div className="rounded-lg border border-white/10 bg-white/5 px-3 py-2">
              <span className="text-gray-400">Recovery:</span>{" "}
              <span className="text-green-400 font-medium">
                {drawdownData.recoveryTrades !== null
                  ? `${drawdownData.recoveryTrades} trades`
                  : "In progress"}
              </span>
            </div>

            <div className="rounded-lg border border-white/10 bg-white/5 px-3 py-2">
              <span className="text-gray-400">DD %:</span>{" "}
              <span className="text-red-400 font-medium">
                {drawdownData.recoveryPercent.toFixed(1)}%
              </span>
            </div>
          </div>
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {showSessions ? (
          <>
            {recentTradesSection}
            <div className="flex min-h-[300px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
              <h2 className="mb-3 text-base font-semibold text-blue-300">
                Session Performance
              </h2>
              <div className="flex flex-1 flex-col gap-4">
                <div className="flex min-h-[240px] flex-col">
                  <p className="mb-2 text-sm text-gray-400">Trades by Session</p>
                  <div className="min-h-0 flex-1">
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
                  <p className="mb-2 text-sm text-gray-400">Session breakdown</p>
                  <div className="grid grid-cols-3 gap-3">
                    {(["London", "NY", "Asia"] as const).map((name) => {
                      const s = sessionBuckets[name]
                      const wr = s.totalTrades
                        ? (s.wins / s.totalTrades) * 100
                        : 0
                      const titleColor =
                        name === "London"
                          ? "text-blue-300"
                          : name === "NY"
                            ? "text-emerald-400"
                            : "text-purple-300"
                      return (
                        <div
                          key={name}
                          className="rounded-lg border border-white/10 bg-white/5 p-3 text-center text-sm"
                        >
                          <p className={`mb-2 font-semibold ${titleColor}`}>
                            {name}
                          </p>
                          <p className="text-gray-300">
                            <span className="text-gray-400">Trades:</span>{" "}
                            {formatNumber(s.totalTrades)}
                          </p>
                          <p className="text-gray-300">
                            <span className="text-gray-400">Win rate:</span>{" "}
                            {wr.toFixed(1)}%
                          </p>
                          <p
                            className={`mt-1 text-lg font-semibold tabular-nums ${
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
          </>
        ) : (
          <div className="lg:col-span-2">{recentTradesSection}</div>
        )}
      </div>
    </div>

  </div>

  {/* SYMBOL + P&L BY WEEKDAY */}
  <div className="grid grid-cols-1 gap-6 lg:grid-cols-3 lg:items-stretch">

    <div className="h-full overflow-x-auto rounded-xl border border-white/10 bg-white/10 p-4 lg:col-span-2">
      <h3 className="mb-2 text-sm text-gray-400">Symbol Performance</h3>

      <table className="w-full min-w-[520px] text-sm">
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

    {pnlByWeekdaySection}

  </div>

          {(showInsights || showBestSetup) ? (
          <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
            {showInsights ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
                <h3 className="mb-2 text-sm text-gray-400">Performance Insights</h3>
                <p className="mb-3 text-xs text-gray-500">
                  Data-driven highlights (min. 3 trades per session, symbol, or
                  direction). Respects current filters.
                </p>
                {insights.length > 0 ? (
                  <div className="space-y-2">
                    {insights.map((text, i) => (
                      <p
                        key={`${i}-${text.slice(0, 24)}`}
                        className="text-sm text-gray-200"
                      >
                        • {text}
                      </p>
                    ))}
                  </div>
                ) : (
                  <p className="text-sm text-gray-400">
                    Not enough sample size yet — need at least 3 trades in a session,
                    symbol, or direction bucket (with current filters).
                  </p>
                )}
            </div>
            ) : null}

            {showBestSetup ? (
            <div
              className={`rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md ${!showInsights ? "md:col-span-2" : ""}`}
            >
              <h3 className="mb-2 text-sm text-gray-400">
                Best Performing Setup
              </h3>
              {bestSetup ? (
                <div className="space-y-2 text-sm text-gray-300">
                  <p>
                    <span className="text-gray-400">Setup:</span>{" "}
                    <span className="text-lg font-semibold text-white">{bestSetup.trade_type}</span>
                  </p>
                  <p>
                    <span className="text-gray-400">Win rate:</span>{" "}
                    <span className="text-lg font-semibold text-white">{bestSetup.winRate.toFixed(1)}%</span>
                  </p>
                  <p>
                    <span className="text-gray-400">Total P&amp;L:</span>{" "}
                    <span
                      className={`text-lg font-semibold tabular-nums ${
                        bestSetup.totalPnL >= 0 ? "text-green-400" : "text-red-400"
                      }`}
                    >
                      {formatCurrency(bestSetup.totalPnL)}
                    </span>
                  </p>
                  <p>
                    <span className="text-gray-400">Trades:</span>{" "}
                    <span className="text-lg font-semibold text-white">{bestSetup.trades}</span>
                  </p>
                </div>
              ) : (
                <p className="text-sm text-gray-400">
                  Need at least 3 trades with the same setup type (and non-empty
                  trade type) to rank setups.
                </p>
              )}
            </div>
            ) : null}
          </div>
          ) : null}

          {(showInsights || showWorstSetup || showWarnings) ? (
          <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
            {showInsights ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
                <h3 className="mb-2 text-sm text-gray-400">Advanced Edge</h3>
                <p className="mb-3 text-xs text-gray-500">
                  Strongest <span className="text-gray-400">combined</span> setup
                  (pairs or triples, min. 3 trades). Same filters as above.
                </p>
                {combinedInsights.length > 0 ? (
                  <div className="space-y-2">
                    {combinedInsights.map((text, i) => (
                      <p
                        key={`combo-${i}-${text.slice(0, 20)}`}
                        className="text-sm font-medium text-emerald-300"
                      >
                        ⭐ {text}
                      </p>
                    ))}
                  </div>
                ) : (
                  <p className="text-sm text-gray-400">
                    No qualifying combined setup yet — need 3+ trades with consistent
                    session, symbol, and direction data.
                  </p>
                )}
            </div>
            ) : null}

            {showWorstSetup ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
              <h3 className="mb-2 text-sm text-gray-400">Risk Insights</h3>
              <p className="mb-3 text-xs text-gray-500">
                Lowest-performing combined setup (same 3+ trade rule as Advanced Edge).
              </p>
              {worstInsight ? (
                <p className="text-lg font-semibold text-red-400">⚠️ {worstInsight}</p>
              ) : (
                <p className="text-sm text-gray-400">
                  No combined setup to rank yet, or filters removed too much data.
                </p>
              )}
            </div>
            ) : null}

            {showWarnings ? (
            <div className="rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md md:col-span-2">
              <h3 className="mb-2 text-sm text-gray-400">Behavior Warnings</h3>
              <p className="mb-3 text-xs text-gray-500">
                Post–loss streak win rate (next 5 trades) and RR sample comparison.
              </p>
              {warnings.length > 0 ? (
                <div className="space-y-2">
                  {warnings.map((w, i) => (
                    <p key={`warn-${i}-${w.slice(0, 16)}`} className="text-sm text-yellow-300">
                      🚨 {w}
                    </p>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-gray-400">
                  No behavioral flags for the current trade set.
                </p>
              )}
            </div>
            ) : null}
          </div>
          ) : null}

          </div>
        </ProGate>
      </div>
    </>
  )
}

function Stat({ title, value, positive }: any) {
  let color = "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="rounded-xl border border-white/10 bg-white/10 p-4 backdrop-blur-md">
      <p className="mb-2 text-sm text-gray-400">{title}</p>
      <p className={`text-lg font-semibold tabular-nums ${color}`}>{value}</p>
    </div>
  )
}
