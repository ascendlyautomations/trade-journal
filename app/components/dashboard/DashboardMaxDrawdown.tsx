"use client"

import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import { dashboardWidgetSectionTitleClass } from "@/app/components/dashboard/dashboardInsightStyles"
import { formatCurrency } from "@/lib/formatCurrency"

export type DashboardMaxDrawdownProps = {
  maxDrawdown: number
  totalTrades?: number
  /** Compact card matches Expectancy / Streaks in the stats column. */
  variant?: "compact" | "panel"
}

export default function DashboardMaxDrawdown({
  maxDrawdown,
  totalTrades = 0,
  variant = "compact",
}: DashboardMaxDrawdownProps) {
  const showEmpty = totalTrades === 0

  if (variant === "compact") {
    return (
      <div className="rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:p-4">
        <h3 className={dashboardWidgetSectionTitleClass}>Max Drawdown</h3>
        {showEmpty ? (
          <p className="text-[11px] text-gray-400 md:text-sm">
            Upload your first trade to unlock this metric.
          </p>
        ) : (
          <>
            <p className="text-xs font-semibold tabular-nums text-red-400 md:text-lg">
              {formatCurrency(maxDrawdown)}
            </p>
            <p className="mt-1 text-[11px] md:text-xs text-gray-400">
              Largest peak-to-trough drop on cumulative P&amp;L.
            </p>
          </>
        )}
      </div>
    )
  }

  return (
    <div className="flex min-h-[120px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
      <h2 className="mb-3 text-sm md:text-base font-semibold text-blue-300">
        Max Drawdown
      </h2>
      {showEmpty ? (
        <DashboardWidgetEmptyState variant="no-trades" className="py-6" />
      ) : (
        <>
          <p className="text-2xl md:text-3xl font-semibold tabular-nums text-red-400">
            {formatCurrency(maxDrawdown)}
          </p>
          <p className="mt-2 text-xs leading-relaxed text-gray-400">
            Largest peak-to-trough drop on cumulative P&amp;L for filtered
            trades, ordered by entry/exit time.
          </p>
        </>
      )}
    </div>
  )
}
