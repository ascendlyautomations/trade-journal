"use client"

import dynamic from "next/dynamic"
import { memo, type ComponentProps } from "react"
import DashboardWidgetEmptyState from "./DashboardWidgetEmptyState"
import { dashboardInsightTitleClass } from "./dashboardInsightStyles"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatRR } from "@/lib/formatDisplay"

const DashboardLongShort = dynamic(() => import("./DashboardLongShort"), {
  loading: () => <div className="h-44 animate-pulse rounded-xl bg-white/5" />,
})
const DashboardHoldTime = dynamic(() => import("./DashboardHoldTime"), {
  loading: () => <div className="h-44 animate-pulse rounded-xl bg-white/5" />,
})
const DashboardWeekdayChart = dynamic(() => import("./DashboardWeekdayChart"), {
  loading: () => <div className="h-48 animate-pulse rounded-lg bg-white/5" />,
})

type SymbolPerformanceRow = {
  ticker: string
  totalTrades: number
  wins: number
  winRate: number
  totalPnL: number
  avgRR: number | null
}

type DashboardAnalyticsProps = {
  symbolPerformanceRows: SymbolPerformanceRow[]
  hasAnyTrades: boolean
  deferredSectionsReady: boolean
  weekdayData: ComponentProps<typeof DashboardWeekdayChart>["data"]
  longShortPerformance: ComponentProps<typeof DashboardLongShort>["performance"]
  holdTimeStats: ComponentProps<typeof DashboardHoldTime>["stats"]
  totalTrades: number
  /** Force Long vs Short comparison table (mobile Analytics tab). */
  longShortLayout?: ComponentProps<typeof DashboardLongShort>["layout"]
}

function formatNumber(value: number) {
  if (value === null || value === undefined) return "-"
  return value.toLocaleString()
}

function DashboardAnalytics({
  symbolPerformanceRows,
  hasAnyTrades,
  deferredSectionsReady,
  weekdayData,
  longShortPerformance,
  holdTimeStats,
  totalTrades,
  longShortLayout = "auto",
}: DashboardAnalyticsProps) {
  return (
    <div className="flex flex-col gap-2 max-md:gap-2 md:gap-3">
      <div className="grid grid-cols-1 gap-2 max-md:gap-2 md:gap-3 lg:grid-cols-3 lg:items-stretch">
        <div className="h-full overflow-x-auto rounded-xl border border-white/10 bg-white/10 p-2.5 max-md:px-2 max-md:pb-1.5 max-md:pt-1.5 md:p-4 lg:col-span-2">
          <h3 className={dashboardInsightTitleClass}>Symbol Performance</h3>

          {symbolPerformanceRows.length === 0 ? (
            <DashboardWidgetEmptyState
              variant={hasAnyTrades ? "needs-more-trades" : "no-trades"}
              showImportCsv={!hasAnyTrades}
              className="py-8"
            />
          ) : (
            <table className="w-full min-w-[520px] text-[11px] md:text-sm">
              <thead>
                <tr className="border-b border-white/10 text-gray-200 md:text-gray-400">
                  <th className="py-1.5 text-center md:py-2">Ticker</th>
                  <th className="py-1.5 text-center md:py-2">Trades</th>
                  <th className="py-1.5 text-center md:py-2">Win %</th>
                  <th className="py-1.5 text-center md:py-2">Total P&amp;L</th>
                  <th className="py-1.5 text-center md:py-2">Avg RR</th>
                </tr>
              </thead>
              <tbody className="text-white">
                {symbolPerformanceRows.map((row) => (
                  <tr
                    key={row.ticker}
                    className="border-b border-white/10 hover:bg-white/10"
                  >
                    <td className="py-1.5 text-center md:py-2">{row.ticker}</td>
                    <td className="py-1.5 text-center md:py-2">
                      {formatNumber(row.totalTrades)}
                    </td>
                    <td className="py-1.5 text-center md:py-2">
                      {row.winRate.toFixed(1)}%
                    </td>
                    <td
                      className={`py-1.5 text-center md:py-2 ${
                        row.totalPnL >= 0 ? "text-green-400" : "text-red-400"
                      }`}
                    >
                      {formatCurrency(row.totalPnL)}
                    </td>
                    <td className="py-1.5 text-center md:py-2">
                      {formatRR(row.avgRR)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <div className="hidden md:block">
          {deferredSectionsReady ? (
            <DashboardWeekdayChart data={weekdayData} totalTrades={totalTrades} />
          ) : (
            <div className="h-48 animate-pulse rounded-xl border border-white/10 bg-white/5" />
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 gap-2 max-md:gap-2 md:gap-3 lg:grid-cols-3 lg:items-stretch">
        <DashboardLongShort
          performance={longShortPerformance}
          totalTrades={totalTrades}
          layout={longShortLayout}
        />
        <div className="lg:col-span-2">
          <DashboardHoldTime stats={holdTimeStats} totalTrades={totalTrades} />
        </div>
      </div>
    </div>
  )
}

export default memo(DashboardAnalytics)
