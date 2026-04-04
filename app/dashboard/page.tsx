"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState, useMemo } from "react"
import { supabase } from "../../lib/supabaseClient"
import { loadStripe } from "@stripe/stripe-js"
import ProGate from "../components/ProGate"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
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

export default function Dashboard() {
  const [trades, setTrades] = useState<any[]>([])
  const [accountFilter, setAccountFilter] = useState("all")
  const [timeFilter, setTimeFilter] = useState("all")
  const [user, setUser] = useState<any>(null)
  const [profile, setProfile] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [subscribing, setSubscribing] = useState(false)

  const stripePromise = loadStripe(
    process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY!
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
    timeFilteredTrades,
    accounts,
    totalTrades,
    winRate,
    totalPnL,
    avgRR,
    biggestLoss,
    maxStreak,
    sessionStats,
    equityData,
    avgWin,
    avgLoss,
    bestDay,
    worstDay,
    symbolStats,
    symbolPerformanceRows,
    sessionBuckets,
    bestSetup,
    weekdayData,
    sessionPieData
  } = useMemo(() => {

    const accounts = Array.from(
      new Set(
        trades
          .filter(t => t.account_type && t.account_id)
          .map(t => `${t.account_type} (${t.account_id})`)
      )
    )

    const filteredTrades = trades
      .filter((trade) => {
        if (accountFilter === "all") return true
        const label = `${trade.account_type} (${trade.account_id})`
        return label === accountFilter
      })
      .sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime())

    const now = new Date()

    const timeFilteredTrades = filteredTrades.filter((t) => {
      const d = new Date(t.created_at)

      if (timeFilter === "daily") {
        return d.toDateString() === now.toDateString()
      }

      if (timeFilter === "weekly") {
        const weekAgo = new Date()
        weekAgo.setDate(now.getDate() - 7)
        return d >= weekAgo
      }

      if (timeFilter === "monthly") {
        return (
          d.getMonth() === now.getMonth() &&
          d.getFullYear() === now.getFullYear()
        )
      }

      return true
    })

    const totalTrades = timeFilteredTrades.length
    const wins = timeFilteredTrades.filter(t => t.pnl > 0)
    const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
    const totalPnL = timeFilteredTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)

    const avgRR =
      timeFilteredTrades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
      (timeFilteredTrades.length || 1)

    const losses = timeFilteredTrades
  .map(t => Number(t.pnl) || 0)
  .filter(p => p < 0)

const biggestLoss = losses.length > 0
  ? Math.min(...losses)
  : 0

    let currentStreak = 0
    let maxStreak = 0
    timeFilteredTrades.forEach(t => {
      if (t.pnl < 0) {
        currentStreak++
        if (currentStreak > maxStreak) maxStreak = currentStreak
      } else {
        currentStreak = 0
      }
    })

    const sessionStats: any = {}
    timeFilteredTrades.forEach(t => {
      if (!sessionStats[t.session]) {
        sessionStats[t.session] = { pnl: 0, trades: 0, wins: 0 }
      }
      sessionStats[t.session].pnl += t.pnl || 0
      sessionStats[t.session].trades += 1
      if (t.pnl > 0) sessionStats[t.session].wins += 1
    })

    const symbolStats: Record<string, any> = {}

    timeFilteredTrades.forEach((t) => {
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

    timeFilteredTrades.forEach((t) => {
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

    timeFilteredTrades.forEach((t) => {
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

    timeFilteredTrades.forEach((t) => {
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
    timeFilteredTrades.forEach((t) => {
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

    function toEST(date: Date) {
      return new Date(date.toLocaleString("en-US", { timeZone: "America/New_York" }))
    }

    function toESTDateString(date: Date) {
      return toEST(date).toISOString().split("T")[0]
    }

    const dailyMap: Record<string, number> = {}

    timeFilteredTrades.forEach((t) => {
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

    const winsOnly = timeFilteredTrades.filter(t => t.pnl > 0)
    const lossesOnly = timeFilteredTrades.filter(t => t.pnl < 0)

    const avgWin =
      winsOnly.reduce((sum, t) => sum + t.pnl, 0) / (winsOnly.length || 1)

    const avgLoss =
      lossesOnly.reduce((sum, t) => sum + t.pnl, 0) / (lossesOnly.length || 1)

    const dates: string[] = []

    if (timeFilteredTrades.length > 0) {
      const first = toEST(new Date(timeFilteredTrades[0].created_at))
      const today = toEST(new Date())

      let current = new Date(first)

      while (current <= today) {
        dates.push(toESTDateString(current))
        current.setDate(current.getDate() + 1)
      }
    } else {
      dates.push(toESTDateString(new Date()))
    }

    let running = 0

    const equityData = dates.map((date) => {
      running += dailyMap[date] || 0

      return {
        date: new Date(date).toLocaleDateString(),
        equity: running
      }
    })

    return {
      filteredTrades,
      timeFilteredTrades,
      accounts,
      totalTrades,
      winRate,
      totalPnL,
      avgRR,
      biggestLoss,
      maxStreak,
      sessionStats,
      equityData,
      avgWin,
      avgLoss,
      bestDay,
      worstDay,
      symbolStats,
      symbolPerformanceRows,
      sessionBuckets,
      bestSetup,
      weekdayData,
      sessionPieData
    }

  }, [trades, accountFilter, timeFilter])

  async function handleSubscribe(userId: string) {
    setSubscribing(true)
    try {
      const res = await fetch("/api/create-checkout-session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ userId }),
      })

      const data = await res.json()

      if (data.url) {
        window.location.href = data.url
      } else {
        alert("Checkout failed")
      }
    } finally {
      setSubscribing(false)
    }
  }

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

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-10">

        <h1 className="text-3xl font-semibold text-center mb-6 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          Dashboard
        </h1>

        {profile && !profile.is_pro && (
          <div className="mb-4 rounded-lg bg-amber-500/10 border border-amber-400/40 text-amber-100 px-4 py-3 text-center text-sm">
            Upgrade to Pro to unlock full features 🚀
          </div>
        )}

        <div className="flex flex-wrap justify-center items-center gap-3 mb-8">
          <select
            value={accountFilter}
            onChange={(e) => setAccountFilter(e.target.value)}
            className="bg-white text-black px-3 py-2 rounded"
          >
            <option value="all">All Accounts</option>
            {accounts.map((acc) => (
              <option key={acc}>{acc}</option>
            ))}
          </select>

          <div className="flex gap-2">
            {["all", "daily", "weekly", "monthly"].map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setTimeFilter(t)}
                className={`px-3 py-1.5 text-sm rounded transition whitespace-nowrap ${
                  timeFilter === t
                    ? "bg-emerald-500 text-white"
                    : "bg-white/10 hover:bg-white/20"
                }`}
              >
                {t.toUpperCase()}
              </button>
            ))}
          </div>
        </div>

        <ProGate isPro={profile?.is_pro}>
          <div className="space-y-8">

  {/* TOP: STATS + CHART */}
  <div className="grid lg:grid-cols-3 gap-8">

    {/* LEFT: STATS */}
    <div className="grid grid-cols-2 gap-4">
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

    {/* RIGHT: CHARTS */}
    <div className="lg:col-span-2 space-y-6">
      <div className="bg-white/5 border border-white/10 p-6 rounded-xl">
        <h2 className="text-lg font-semibold mb-4 text-blue-300">
          Equity Curve
        </h2>

        <ResponsiveContainer width="100%" height={350}>
          <LineChart data={equityData}>
            <CartesianGrid stroke="#334155" />
            <XAxis dataKey="date" stroke="#94a3b8" />
            <YAxis stroke="#94a3b8" />
            <Tooltip formatter={(value: any) => `$${value.toLocaleString()}`} />
            <Line type="monotone" dataKey="equity" stroke="#22c55e" strokeWidth={3} dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white/5 border border-white/10 p-6 rounded-xl min-h-[320px]">
          <h2 className="text-lg font-semibold mb-4 text-blue-300">
            P&amp;L by Weekday
          </h2>
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={weekdayData}>
              <CartesianGrid stroke="#334155" />
              <XAxis dataKey="day" stroke="#94a3b8" />
              <YAxis stroke="#94a3b8" />
              <Tooltip formatter={(value: any) => formatCurrency(Number(value))} />
              <Line type="monotone" dataKey="pnl" stroke="#38bdf8" strokeWidth={2} dot={{ r: 4, fill: "#38bdf8" }} />
            </LineChart>
          </ResponsiveContainer>
        </div>

        <div className="bg-white/5 border border-white/10 p-6 rounded-xl min-h-[320px]">
          <h2 className="text-lg font-semibold mb-4 text-blue-300">
            Trades by Session
          </h2>
          <ResponsiveContainer width="100%" height={280}>
            <PieChart>
              <Pie
                data={sessionPieData}
                dataKey="value"
                nameKey="name"
                cx="50%"
                cy="50%"
                outerRadius={90}
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
    </div>

  </div>

  {/* SYMBOL + RECENT */}
  <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">

    <div className="lg:col-span-2 bg-white/5 border border-white/10 p-4 rounded-xl overflow-x-auto">
      <h3 className="text-blue-300 font-semibold mb-3">Symbol Performance</h3>

      <table className="w-full min-w-[520px] text-sm">
        <thead>
          <tr className="border-b border-white/10 text-gray-400">
            <th className="py-2">Ticker</th>
            <th>Trades</th>
            <th>Win %</th>
            <th>Total P&L</th>
            <th>Avg RR</th>
          </tr>
        </thead>
        <tbody>
          {symbolPerformanceRows.map((row) => (
            <tr key={row.ticker} className="border-b border-white/10 hover:bg-white/10">
              <td>{row.ticker}</td>
              <td>{formatNumber(row.totalTrades)}</td>
              <td>{row.winRate.toFixed(1)}%</td>
              <td className={row.totalPnL >= 0 ? "text-green-400" : "text-red-400"}>
                {formatCurrency(row.totalPnL)}
              </td>
              <td>{row.avgRR.toFixed(2)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>

    <div className="bg-white/5 border border-white/10 p-4 rounded-xl">
      <h3 className="text-blue-300 font-semibold mb-2">Recent Trades</h3>

      {timeFilteredTrades.slice(-5).reverse().map((t) => (
        <div key={t.id} className="flex justify-between py-1 border-b border-white/10 text-sm">
          <span>{t.ticker}</span>
          <span className={t.pnl >= 0 ? "text-green-400" : "text-red-400"}>
            {formatCurrency(t.pnl)}
          </span>
        </div>
      ))}
    </div>

  </div>




</div>

          <div className="mt-8 grid grid-cols-1 md:grid-cols-3 gap-4 max-w-5xl mx-auto lg:max-w-none">
            {(["London", "NY", "Asia"] as const).map((name) => {
              const s = sessionBuckets[name]
              const wr = s.totalTrades ? (s.wins / s.totalTrades) * 100 : 0
              const accent =
                name === "London"
                  ? "border-blue-400/40 shadow-blue-500/10"
                  : name === "NY"
                  ? "border-emerald-400/40 shadow-emerald-500/10"
                  : "border-purple-400/40 shadow-purple-500/10"
              const titleColor =
                name === "London"
                  ? "text-blue-300"
                  : name === "NY"
                  ? "text-emerald-400"
                  : "text-purple-300"

              return (
                <div
                  key={name}
                  className={`bg-white/5 border ${accent} p-4 rounded-xl shadow-lg`}
                >
                  <h3 className={`font-semibold mb-3 ${titleColor}`}>{name}</h3>
                  <p className="text-sm text-gray-300">
                    <span className="text-gray-400">Trades:</span> {formatNumber(s.totalTrades)}
                  </p>
                  <p className="text-sm text-gray-300">
                    <span className="text-gray-400">Win Rate:</span> {wr.toFixed(1)}%
                  </p>
                  <p className={`text-sm font-medium mt-1 ${s.totalPnL >= 0 ? "text-green-400" : "text-red-400"}`}>
                    <span className="text-gray-400 font-normal">P&amp;L:</span> {formatCurrency(s.totalPnL)}
                  </p>
                </div>
              )
            })}
          </div>

          <div className="mt-8 max-w-5xl mx-auto lg:max-w-none">
            <div className="bg-white/5 border border-white/10 p-4 rounded-xl">
              <h3 className="text-blue-300 font-semibold mb-3">Best Performing Setup</h3>
              {bestSetup ? (
                <div className="text-sm space-y-2 text-gray-300">
                  <p>
                    <span className="text-gray-400">Setup:</span>{" "}
                    <span className="text-white font-medium">{bestSetup.trade_type}</span>
                  </p>
                  <p>
                    <span className="text-gray-400">Win rate:</span> {bestSetup.winRate.toFixed(1)}%
                  </p>
                  <p className={bestSetup.totalPnL >= 0 ? "text-green-400" : "text-red-400"}>
                    <span className="text-gray-400">Total P&amp;L:</span> {formatCurrency(bestSetup.totalPnL)}
                  </p>
                  <p>
                    <span className="text-gray-400">Trades:</span> {bestSetup.trades}
                  </p>
                </div>
              ) : (
                <p className="text-gray-400 text-sm">
                  Need at least 3 trades with the same setup type (and non-empty trade type) to rank setups.
                </p>
              )}
            </div>
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
    <div className="bg-white/5 border border-white/10 p-4 rounded-xl">
      <p className="text-xs text-blue-300">{title}</p>
      <p className={`text-lg font-semibold ${color}`}>
        {value}
      </p>
    </div>
  )
}
