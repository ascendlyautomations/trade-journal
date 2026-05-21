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

export type WeekdayChartPoint = {
  day: string
  pnl: number
}

export type DashboardWeekdayChartProps = {
  data: WeekdayChartPoint[]
}

export default function DashboardWeekdayChart({ data }: DashboardWeekdayChartProps) {
  return (
    <div className="flex min-h-[300px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
      <h2 className="mb-3 text-sm md:text-base font-semibold text-blue-300">
        P&amp;L by Weekday
      </h2>
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
    </div>
  )
}
