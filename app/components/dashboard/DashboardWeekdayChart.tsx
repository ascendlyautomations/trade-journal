"use client"

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ResponsiveContainer,
} from "recharts"
import EmptyState from "@/app/components/ui/EmptyState"
import { formatPnlCurrency } from "@/lib/formatMoney"

export type WeekdayChartPoint = {
  day: string
  pnl: number
}

export type DashboardWeekdayChartProps = {
  data: WeekdayChartPoint[]
  totalTrades?: number
}

export default function DashboardWeekdayChart({
  data,
  totalTrades = 0,
}: DashboardWeekdayChartProps) {
  const showEmpty = totalTrades === 0

  return (
    <div className="flex min-h-[260px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:min-h-[300px] md:p-4">
      <h2 className="mb-2 text-xs font-semibold text-blue-300 md:mb-3 md:text-base">
        P&amp;L by Weekday
      </h2>
      {showEmpty ? (
        <EmptyState
          title="Not Enough Data Yet"
          description="Add more trades to unlock detailed analytics."
          className="py-5 md:py-8"
        />
      ) : (
      <div className="w-full overflow-hidden">
        <ResponsiveContainer width="100%" height={280}>
          <LineChart
            data={data}
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
                formatPnlCurrency(Number(value), {
                  minimumFractionDigits: 0,
                  maximumFractionDigits: 2,
                })
              }
              labelFormatter={(label) => `${label}`}
            />
            <Line
              type="monotone"
              dataKey="pnl"
              stroke="#38bdf8"
              strokeWidth={2}
              dot={{ r: 4, fill: "#38bdf8" }}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
      )}
    </div>
  )
}
