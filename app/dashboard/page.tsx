"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState, useMemo } from "react"
import { supabase } from "../../lib/supabaseClient"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ResponsiveContainer
} from "recharts"

export default function Dashboard() {
  const [trades, setTrades] = useState<any[]>([])
  const [accountFilter, setAccountFilter] = useState("all")
  const [user, setUser] = useState<any>(null)
  const [profile, setProfile] = useState<any>(null)
  const [loading, setLoading] = useState(true)

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
    accounts,
    totalTrades,
    winRate,
    totalPnL,
    avgRR,
    biggestLoss,
    maxStreak,
    sessionStats,
    equityData
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

    const totalTrades = filteredTrades.length
    const wins = filteredTrades.filter(t => t.pnl > 0)
    const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
    const totalPnL = filteredTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)

    const avgRR =
      filteredTrades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
      (filteredTrades.length || 1)

    const biggestLoss =
      Math.min(...filteredTrades.map(t => t.pnl || 0), 0)

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

    const dates: string[] = []

    if (filteredTrades.length > 0) {
      const first = toEST(new Date(filteredTrades[0].created_at))
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
      accounts,
      totalTrades,
      winRate,
      totalPnL,
      avgRR,
      biggestLoss,
      maxStreak,
      sessionStats,
      equityData
    }

  }, [trades, accountFilter])

  const insights = ["You're on track. Keep executing."]

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



        <div className="flex justify-center mb-8">
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
        </div>

        <div className="grid lg:grid-cols-3 gap-8">

          <div className="space-y-6">
            <div className="grid grid-cols-2 gap-4">
              <Stat title="Trades" value={formatNumber(totalTrades)} />
              <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />
              <Stat title="P&L" value={formatCurrency(totalPnL)} positive={totalPnL >= 0} />
              <Stat title="Avg RR" value={avgRR.toFixed(2)} />
              <Stat title="Big Loss" value={formatCurrency(biggestLoss)} positive={false} />
              <Stat title="Streak" value={maxStreak} />
            </div>

            {Object.keys(sessionStats).map((session) => {
              const s = sessionStats[session]
              const wr = s.trades ? (s.wins / s.trades) * 100 : 0

              return (
                <div key={session} className="bg-white/5 border border-white/10 p-4 rounded-xl">
                  <h3 className="font-semibold text-blue-300">{session}</h3>
                  <p>P&L: {formatCurrency(s.pnl)}</p>
                  <p>Trades: {formatNumber(s.trades)}</p>
                  <p>Win: {wr.toFixed(1)}%</p>
                </div>
              )
            })}
          </div>

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

            <div className="bg-gradient-to-r from-blue-500/10 to-emerald-500/10 border border-white/10 p-5 rounded-xl">
              <h3 className="text-blue-300 font-semibold mb-3">
                Smart Insights
              </h3>
              <ul className="text-gray-300 text-sm space-y-2">
                {insights.map((i, index) => (
                  <li key={index}>{i}</li>
                ))}
              </ul>
            </div>
          </div>

        </div>
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