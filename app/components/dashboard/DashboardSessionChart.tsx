"use client"

import {
  PieChart,
  Pie,
  Cell,
  Tooltip,
  ResponsiveContainer,
} from "recharts"
import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import { dashboardWidgetSubtitleClass } from "@/app/components/dashboard/dashboardInsightStyles"
import { chartTooltipStyles } from "@/lib/chartTheme"
import { formatCurrency } from "@/lib/formatCurrency"
import {
  DASHBOARD_SESSION_COLORS,
  DASHBOARD_SESSION_DISPLAY_ORDER,
  type DashboardSessionBucket,
} from "@/lib/dashboardSessionBuckets"
import {
  READABLE_LABEL_CLASS,
  READABLE_PRIMARY_CLASS,
} from "@/lib/readableTextStyles"

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

export type SessionBuckets = Record<DashboardSessionBucket, SessionBucketStats>

export type DashboardSessionChartProps = {
  sessionPieData: SessionPiePoint[]
  sessionBuckets: SessionBuckets
  totalTrades?: number
}

export default function DashboardSessionChart({
  sessionPieData,
  sessionBuckets,
  totalTrades = 0,
}: DashboardSessionChartProps) {
  const showEmpty = totalTrades === 0

  return (
    <div className="flex min-h-[260px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:min-h-[300px] md:p-4">
      <h2 className="mb-2 text-xs font-semibold text-blue-300 md:mb-3 md:text-base">
        Session Performance
      </h2>
      {showEmpty ? (
        <DashboardWidgetEmptyState
          variant="no-trades"
          showImportCsv
          className="py-5 md:py-8"
        />
      ) : (
      <div className="flex flex-1 flex-col gap-3 md:gap-4">
        <div className="flex min-h-[220px] flex-col md:min-h-[240px]">
          <p className={dashboardWidgetSubtitleClass}>Trades by Session</p>
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
                  {sessionPieData.map((entry) => (
                    <Cell
                      key={`cell-${entry.name}`}
                      fill={
                        DASHBOARD_SESSION_COLORS[
                          entry.name as DashboardSessionBucket
                        ] ?? "#9ca3af"
                      }
                    />
                  ))}
                </Pie>
                <Tooltip {...chartTooltipStyles} />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </div>
        <div className="flex flex-col">
          <p className={dashboardWidgetSubtitleClass}>Session breakdown</p>
          <div className="grid grid-cols-3 gap-1.5 md:gap-3">
            {DASHBOARD_SESSION_DISPLAY_ORDER.map((name) => {
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
                  className="rounded-lg border border-white/10 bg-white/5 p-1.5 text-center text-[10px] md:p-3 md:text-sm"
                >
                  <p className={`mb-1 font-semibold md:mb-2 ${titleColor}`}>{name}</p>
                  <p className={READABLE_PRIMARY_CLASS}>
                    <span className={READABLE_LABEL_CLASS}>Trades:</span>{" "}
                    {formatNumber(s.totalTrades)}
                  </p>
                  <p className={READABLE_PRIMARY_CLASS}>
                    <span className={READABLE_LABEL_CLASS}>Win rate:</span>{" "}
                    {wr.toFixed(1)}%
                  </p>
                  <p
                    className={`mt-0.5 text-xs font-semibold tabular-nums md:mt-1 md:text-lg ${
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
      )}
    </div>
  )
}
