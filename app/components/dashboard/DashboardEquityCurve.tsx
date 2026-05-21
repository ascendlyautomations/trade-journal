"use client"

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  CartesianGrid,
  ResponsiveContainer,
} from "recharts"
import { formatEST } from "@/lib/formatEST"
import { formatCurrency } from "@/lib/formatCurrency"

export type EquityChartPoint = {
  date: string
  equity: number
}

export type DashboardEquityCurveProps = {
  data: EquityChartPoint[]
  variant: "mobile" | "desktop"
  profitFactor?: number
  currentStreak?: number
  avgDay?: number
  consistency?: number
}

export default function DashboardEquityCurve({
  data,
  variant,
  profitFactor = 0,
  currentStreak = 0,
  avgDay = 0,
  consistency = 0,
}: DashboardEquityCurveProps) {
  if (variant === "mobile") {
    return (
      <div className="col-span-2 block md:hidden overflow-visible rounded-xl border border-white/10 bg-white/10 p-3 backdrop-blur-md">
        <h2 className="mb-3 text-sm font-semibold text-blue-300">Equity Curve</h2>
        <div className="h-[240px] w-full">
          <ResponsiveContainer width="100%" height={240}>
            <LineChart
              data={data}
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
    )
  }

  return (
    <div className="hidden md:block overflow-visible rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
      <h2 className="text-sm md:text-base font-semibold mb-3 text-blue-300">
        Equity Curve
      </h2>

      <div className="w-full h-[300px]">
        <ResponsiveContainer width="100%" height={300}>
          <LineChart
            data={data}
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
  )
}
