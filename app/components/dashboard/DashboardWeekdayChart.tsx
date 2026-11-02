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
import ChartWhenSized from "@/app/components/dashboard/ChartWhenSized"
import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import {
  chartAxisTick,
  chartCartesianGridProps,
  chartTooltipStyles,
} from "@/lib/chartTheme"
import { formatPnlCurrency } from "@/lib/formatMoney"
import {
  formatMobileWebChartAxisUsd,
  MOBILE_WEB_CHART,
} from "@/lib/mobileWebAnalytics"

export type WeekdayChartPoint = {
  day: string
  pnl: number
}

export type DashboardWeekdayChartProps = {
  data: WeekdayChartPoint[]
  totalTrades?: number
  /** Drop outer card chrome when wrapped in a phone chart block. */
  embedded?: boolean
}

function WeekdayLineChart({
  data,
  margin,
  tickSize = 12,
  compactAxis = false,
}: {
  data: WeekdayChartPoint[]
  margin: { top: number; right: number; left: number; bottom: number }
  tickSize?: number
  compactAxis?: boolean
}) {
  return (
    <LineChart data={data} margin={margin}>
      <CartesianGrid {...chartCartesianGridProps} />
      <XAxis dataKey="day" {...chartAxisTick(tickSize)} />
      <YAxis
        {...chartAxisTick(tickSize)}
        width={compactAxis ? MOBILE_WEB_CHART.yAxisWidth : undefined}
        tickFormatter={(value) =>
          compactAxis
            ? formatMobileWebChartAxisUsd(Number(value))
            : Number(value) < 0
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
        {...(compactAxis
          ? {
              wrapperStyle: { maxWidth: 200, zIndex: 20 },
              allowEscapeViewBox: { x: true, y: true },
            }
          : {})}
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
  embedded = false,
}: DashboardWeekdayChartProps) {
  const showEmpty = totalTrades === 0

  const MOBILE_CHART_HEIGHT = MOBILE_WEB_CHART.weekdayHeight
  const DESKTOP_CHART_HEIGHT = 280

  return (
    <div
      className={
        embedded
          ? "w-full"
          : "flex h-full min-h-[260px] flex-col rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md max-md:h-auto max-md:min-h-0 max-md:px-2 max-md:pb-1 max-md:pt-1.5 md:min-h-[300px] md:p-4"
      }
    >
      {embedded ? null : (
        <h2 className="mb-2 text-xs font-semibold text-blue-300 max-md:mb-1 md:mb-3 md:text-base">
          P&amp;L by Weekday
        </h2>
      )}
      {showEmpty ? (
        <DashboardWidgetEmptyState
          variant="no-trades"
          showImportCsv
          className="py-5 md:py-8"
        />
      ) : (
        <>
          <div className="w-full overflow-hidden md:hidden">
            <ChartWhenSized height={MOBILE_CHART_HEIGHT} className="w-full">
              <ResponsiveContainer width="100%" height={MOBILE_CHART_HEIGHT}>
                <WeekdayLineChart
                  data={data}
                  margin={MOBILE_WEB_CHART.weekdayMargin}
                  tickSize={MOBILE_WEB_CHART.tickSize}
                  compactAxis
                />
              </ResponsiveContainer>
            </ChartWhenSized>
          </div>
          <div className="hidden w-full overflow-hidden md:block">
            <ChartWhenSized height={DESKTOP_CHART_HEIGHT} className="w-full">
              <ResponsiveContainer width="100%" height={DESKTOP_CHART_HEIGHT}>
                <WeekdayLineChart
                  data={data}
                  margin={{ top: 10, right: 20, left: 20, bottom: 20 }}
                />
              </ResponsiveContainer>
            </ChartWhenSized>
          </div>
        </>
      )}
    </div>
  )
}
