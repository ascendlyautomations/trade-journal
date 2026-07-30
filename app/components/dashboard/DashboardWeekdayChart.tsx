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
import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import {
  chartAxisTick,
  chartCartesianGridProps,
  chartTooltipStyles,
} from "@/lib/chartTheme"
import { formatPnlCurrency } from "@/lib/formatMoney"

export type WeekdayChartPoint = {
  day: string
  pnl: number
}

export type DashboardWeekdayChartProps = {
  data: WeekdayChartPoint[]
  totalTrades?: number
}

function WeekdayLineChart({
  data,
  margin,
}: {
  data: WeekdayChartPoint[]
  margin: { top: number; right: number; left: number; bottom: number }
}) {
  return (
    <LineChart data={data} margin={margin}>
      <CartesianGrid {...chartCartesianGridProps} />
      <XAxis dataKey="day" {...chartAxisTick(12)} />
      <YAxis
        {...chartAxisTick(12)}
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
        {...chartTooltipStyles}
      />
      <Line
        type="monotone"
        dataKey="pnl"
        stroke="#38bdf8"
        strokeWidth={2}
        dot={{ r: 4, fill: "#38bdf8" }}
      />
    </LineChart>
  )
}

export default function DashboardWeekdayChart({
  data,
  totalTrades = 0,
}: DashboardWeekdayChartProps) {
  const showEmpty = totalTrades === 0

  // Empty blue under the plot came from:
  // 1) card padding-bottom (p-2.5)
  // 2) title mb-2
  // 3) h-full stretching the card past title+chart
  // 4) LineChart margin.bottom (transparent SVG → card shows through)
  // ResponsiveContainer height stays 280 on both breakpoints.
  return (
    <div className="flex h-full min-h-[260px] flex-col rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md max-md:h-auto max-md:min-h-0 max-md:px-2.5 max-md:pb-1 max-md:pt-2 md:min-h-[300px] md:p-4">
      <h2 className="mb-2 text-xs font-semibold text-blue-300 max-md:mb-1 md:mb-3 md:text-base">
        P&amp;L by Weekday
      </h2>
      {showEmpty ? (
        <DashboardWidgetEmptyState
          variant="no-trades"
          showImportCsv
          className="py-5 md:py-8"
        />
      ) : (
        <>
          <div className="w-full overflow-hidden md:hidden">
            <ResponsiveContainer width="100%" height={280}>
              <WeekdayLineChart
                data={data}
                margin={{ top: 8, right: 12, left: 8, bottom: 4 }}
              />
            </ResponsiveContainer>
          </div>
          <div className="hidden w-full overflow-hidden md:block">
            <ResponsiveContainer width="100%" height={280}>
              <WeekdayLineChart
                data={data}
                margin={{ top: 10, right: 20, left: 20, bottom: 20 }}
              />
            </ResponsiveContainer>
          </div>
        </>
      )}
    </div>
  )
}
