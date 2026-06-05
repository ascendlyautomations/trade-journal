"use client"

import {
  PieChart,
  Pie,
  Cell,
  Tooltip,
  ResponsiveContainer,
} from "recharts"
import { formatCurrency } from "@/lib/formatCurrency"

function formatNumber(value: number) {
  if (value === null || value === undefined) return "-"
  return value.toLocaleString()
}

export type SessionPiePoint = {
  name: string
  value: number
}

export type SessionBucketStats = {
  totalTrades: number
  wins: number
  totalPnL: number
}

export type SessionBuckets = Record<
  "London" | "NY" | "Asia",
  SessionBucketStats
>

export type DashboardSessionChartProps = {
  sessionPieData: SessionPiePoint[]
  sessionBuckets: SessionBuckets
}

export default function DashboardSessionChart({
  sessionPieData,
  sessionBuckets,
}: DashboardSessionChartProps) {
  return (
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
                  label={false}
                  labelLine={false}
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
}
