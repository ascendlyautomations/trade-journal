"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ResponsiveContainer,
  Legend
} from "recharts"

export default function Leaderboard() {
  const [trades, setTrades] = useState<any[]>([])
  const [userId, setUserId] = useState<string | null>(null)
  const [view, setView] = useState("daily")

  useEffect(() => {
    fetchData()
  }, [])

  async function fetchData() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    if (user) setUserId(user.id)

    const { data } = await supabase
      .from("trades")
      .select("user_id, pnl, rr, created_at")

    if (data) setTrades(data)
  }

  // 🔥 EST TIME
  function toEST(date: Date) {
    return new Date(
      date.toLocaleString("en-US", {
        timeZone: "America/New_York"
      })
    )
  }

  function getKey(date: Date): string {
    const est = toEST(date)

    if (view === "daily") return est.toLocaleDateString()

    if (view === "weekly") {
      const first = new Date(est)
      first.setDate(est.getDate() - est.getDay())
      return first.toLocaleDateString()
    }

    if (view === "monthly") {
      return `${est.getMonth() + 1}/${est.getFullYear()}`
    }

    return est.toLocaleDateString()
  }

  function getTodayKey() {
    return getKey(new Date())
  }

  const grouped: any = {}

  trades.forEach((t) => {
    const estDate = toEST(new Date(t.created_at))
    const key = getKey(estDate)

    if (!grouped[key]) grouped[key] = {}

    if (!grouped[key][t.user_id]) {
      grouped[key][t.user_id] = {
        pnl: 0,
        rr: 0,
        count: 0
      }
    }

    grouped[key][t.user_id].pnl += t.pnl || 0
    grouped[key][t.user_id].rr += t.rr || 0
    grouped[key][t.user_id].count += 1
  })

  // 🔥 FORCE TODAY
  const todayKey = getTodayKey()

  if (!grouped[todayKey]) {
    grouped[todayKey] = {
      placeholder: { pnl: 0, rr: 0, count: 0 }
    }
  }

  const sortedKeys = Object.keys(grouped).sort(
    (a, b) => new Date(a).getTime() - new Date(b).getTime()
  )

  const chartData = sortedKeys.map((key) => {
    const users = Object.values(grouped[key])
    const pnls = users.map((u: any) => u.pnl)

    const avg =
      pnls.reduce((a: number, b: number) => a + b, 0) / pnls.length

    const best = Math.max(...pnls)
    const worst = Math.min(...pnls)

    const yourData = grouped[key][userId || ""] || { pnl: null }

    return {
      label: key,
      average: avg,
      best,
      worst,
      you: yourData.pnl
    }
  })

  // 🔥 FILTER YOUR TRADES BASED ON VIEW
  const yourTrades = trades.filter((t) => t.user_id === userId)

  const filteredYourTrades = yourTrades.filter((t) => {
    return getKey(new Date(t.created_at)) === todayKey
  })

  const yourTradeCount = filteredYourTrades.length

  // 🔥 FIXED STATS (NOW RESPECT VIEW)

  const yourAvgPnl =
    filteredYourTrades.length > 0
      ? filteredYourTrades.reduce((sum, t) => sum + (t.pnl || 0), 0) /
        filteredYourTrades.length
      : 0

  const yourAvgRR =
    filteredYourTrades.length > 0
      ? filteredYourTrades.reduce((sum, t) => sum + (t.rr || 0), 0) /
        filteredYourTrades.length
      : 0

  const globalFilteredTrades = trades.filter((t) => {
    return getKey(new Date(t.created_at)) === todayKey
  })

  const globalAvgPnl =
    globalFilteredTrades.length > 0
      ? globalFilteredTrades.reduce((sum, t) => sum + (t.pnl || 0), 0) /
        globalFilteredTrades.length
      : 0

  const globalAvgRR =
    globalFilteredTrades.length > 0
      ? globalFilteredTrades.reduce((sum, t) => sum + (t.rr || 0), 0) /
        globalFilteredTrades.length
      : 0

  // 🔥 PERCENTILE BASED ON CURRENT VIEW
  const userTotals: number[] = []

  if (grouped[todayKey]) {
    Object.values(grouped[todayKey]).forEach((u: any) => {
      userTotals.push(u.pnl)
    })
  }

  const yourTotal =
    filteredYourTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)

  const betterThan =
    userTotals.filter((p) => p < yourTotal).length /
    (userTotals.length || 1)

  const percentile = (betterThan * 100).toFixed(1)

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-10">

        <h1 className="text-3xl font-semibold text-center mb-6 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          Performance Leaderboard
        </h1>

        <div className="flex justify-center mb-8">
          <select
            value={view}
            onChange={(e) => setView(e.target.value)}
            className="bg-[#1e293b] border border-white/10 px-4 py-2 rounded"
          >
            <option value="daily">Daily</option>
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
          </select>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 max-w-7xl mx-auto">

          <div className="lg:col-span-2 bg-white/5 border border-white/10 rounded-xl p-6 backdrop-blur-md">

            <h2 className="mb-4 text-blue-300 font-semibold text-lg">
              Performance Comparison
            </h2>

            <ResponsiveContainer width="100%" height={400}>
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                <XAxis dataKey="label" stroke="#94a3b8" />
                <YAxis stroke="#94a3b8" />
                <Tooltip />
                <Legend />

                <Line type="monotone" dataKey="average" stroke="#3b82f6" />
                <Line type="monotone" dataKey="best" stroke="#22c55e" />
                <Line type="monotone" dataKey="worst" stroke="#f87171" />
                <Line type="monotone" dataKey="you" stroke="#ffffff" strokeWidth={3} />
              </LineChart>
            </ResponsiveContainer>

          </div>

          <div className="bg-white/5 border border-white/10 rounded-xl p-6 backdrop-blur-md space-y-4">

            <h2 className="text-lg font-semibold text-blue-300">
              Your Stats
            </h2>

            <div>Trades ({view}): {yourTradeCount}</div>
            <div>Avg P&L: ${yourAvgPnl.toFixed(2)}</div>
            <div>Avg RR: {yourAvgRR.toFixed(2)}</div>
            <div>Percentile: Top {percentile}%</div>

            <h2 className="text-lg font-semibold text-blue-300 mt-4">
              Global Stats
            </h2>

            <div>Avg P&L: ${globalAvgPnl.toFixed(2)}</div>
            <div>Avg RR: {globalAvgRR.toFixed(2)}</div>
            <div>Total Trades: {globalFilteredTrades.length}</div>

          </div>

        </div>

      </div>
    </>
  )
}