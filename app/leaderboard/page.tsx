"use client"

import Navbar from "../components/Navbar"
import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ResponsiveContainer,
  Legend,
} from "recharts"
import {
  buildLeaderboardChartData,
  type LeaderboardView,
  type TradeForLeaderboard,
} from "../../lib/leaderboardChart"
import { formatPnlCurrency } from "../../lib/formatMoney"

type TooltipPayload = {
  name?: string
  value?: number
  dataKey?: string | number
  color?: string
}

function LeaderboardTooltip({
  active,
  payload,
  label,
}: {
  active?: boolean
  payload?: TooltipPayload[]
  label?: string
}) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white shadow-lg">
      {label != null ? (
        <p className="mb-1 border-b border-white/10 pb-1 text-gray-300">{label}</p>
      ) : null}
      {payload.map((entry, i) => (
        <p key={String(entry.dataKey ?? i)} className="font-medium" style={{ color: entry.color }}>
          {entry.name ?? entry.dataKey}:{" "}
          {formatPnlCurrency(Number(entry.value), {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
          })}
        </p>
      ))}
    </div>
  )
}

export default function Leaderboard() {
  const [trades, setTrades] = useState<TradeForLeaderboard[]>([])
  const [userId, setUserId] = useState<string | null>(null)
  const [view, setView] = useState<LeaderboardView>("daily")

  useEffect(() => {
    fetchData()
  }, [])

  async function fetchData() {
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (user) setUserId(user.id)

    const { data } = await supabase
      .from("trades")
      .select("user_id, pnl, rr, created_at")

    if (data) setTrades(data as TradeForLeaderboard[])
  }

  const { chartData, todayStats } = useMemo(
    () => buildLeaderboardChartData(trades, view, userId),
    [trades, view, userId]
  )

  const yAxisTickFormatter = useCallback((v: number) => {
    return formatPnlCurrency(Number(v), {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    })
  }, [])

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-10">
        <h1 className="text-3xl font-semibold text-center mb-6 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          Leaderboard
        </h1>

        <div className="flex justify-center mb-8">
          <select
            value={view}
            onChange={(e) => setView(e.target.value as LeaderboardView)}
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
                <YAxis stroke="#94a3b8" tickFormatter={yAxisTickFormatter} width={72} />
                <Tooltip content={(props) => <LeaderboardTooltip {...props} />} />
                <Legend />

                <Line
                  type="monotone"
                  name="Average"
                  dataKey="average"
                  stroke="#3b82f6"
                  dot={false}
                />
                <Line
                  type="monotone"
                  name="Best"
                  dataKey="best"
                  stroke="#22c55e"
                  dot={false}
                />
                <Line
                  type="monotone"
                  name="Worst"
                  dataKey="worst"
                  stroke="#f87171"
                  dot={false}
                />
                <Line
                  type="monotone"
                  name="You"
                  dataKey="you"
                  stroke="#ffffff"
                  strokeWidth={3}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>

          <div className="bg-white/5 border border-white/10 rounded-xl p-6 backdrop-blur-md space-y-4">
            <h2 className="text-lg font-semibold text-blue-300">Your Stats</h2>

            <div>Trades ({view}): {todayStats.yourTradeCount}</div>
            <div>Avg P&L: {formatPnlCurrency(todayStats.yourAvgPnl)}</div>
            <div>
              Avg RR:{" "}
              {todayStats.yourAvgRR === null
                ? "—"
                : todayStats.yourAvgRR.toFixed(2)}
            </div>
            <div>
              Percentile: Top{" "}
              {todayStats.percentileTopPct === "—"
                ? "—"
                : `${todayStats.percentileTopPct}%`}
            </div>

            <h2 className="text-lg font-semibold text-blue-300 mt-4">
              Global Stats
            </h2>

            <div>Avg P&L: {formatPnlCurrency(todayStats.globalAvgPnl)}</div>
            <div>
              Avg RR:{" "}
              {todayStats.globalAvgRR === null
                ? "—"
                : todayStats.globalAvgRR.toFixed(2)}
            </div>
            <div>Total Trades: {todayStats.globalTradeCount}</div>
          </div>
        </div>
      </div>
    </>
  )
}
