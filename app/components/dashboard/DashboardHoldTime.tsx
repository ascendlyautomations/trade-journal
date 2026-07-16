"use client"

import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import { formatCurrency } from "@/lib/formatCurrency"
import type { DurationExtreme, HoldTimeStats } from "@/lib/dashboardHoldTimeStats"
import { formatHoldDurationSeconds } from "@/lib/tradeTimingDisplay"

function formatDuration(seconds: number | null | undefined) {
  if (seconds == null) return "—"
  return formatHoldDurationSeconds(Math.round(seconds)) ?? "—"
}

type ExtremeRowProps = {
  label: string
  extreme: DurationExtreme | null
  pnlClass: string
}

function ExtremeRow({ label, extreme, pnlClass }: ExtremeRowProps) {
  return (
    <div className="rounded-lg border border-white/10 bg-white/5 p-2.5 text-[11px] md:p-3 md:text-sm">
      <p className="mb-2 font-medium text-gray-300">{label}</p>
      {extreme ? (
        <div className="space-y-1 text-gray-200">
          <p>
            <span className="text-gray-400">Duration:</span>{" "}
            {formatDuration(extreme.durationSeconds)}
          </p>
          <p>
            <span className="text-gray-400">P&amp;L:</span>{" "}
            <span className={`font-semibold tabular-nums ${pnlClass}`}>
              {formatCurrency(extreme.pnl)}
            </span>
          </p>
        </div>
      ) : (
        <p className="text-gray-400">No matching trades</p>
      )}
    </div>
  )
}

export type DashboardHoldTimeProps = {
  stats: HoldTimeStats
  totalTrades?: number
}

export default function DashboardHoldTime({
  stats,
  totalTrades = 0,
}: DashboardHoldTimeProps) {
  const showEmpty = totalTrades === 0

  return (
    <div className="flex min-h-[180px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:min-h-[200px] md:p-4">
      <h2 className="mb-2 text-xs font-semibold text-blue-300 md:mb-3 md:text-base">
        Hold Time
      </h2>

      {showEmpty ? (
        <DashboardWidgetEmptyState
          variant="no-trades"
          showImportCsv
          className="py-5 md:py-8"
        />
      ) : !stats.hasDurationData ? (
        <DashboardWidgetEmptyState variant="needs-duration" className="py-8" />
      ) : (
        <div className="space-y-3 md:space-y-4">
          <div className="flex min-h-[76px] flex-col items-center justify-center rounded-xl border border-white/10 bg-white/5 p-2.5 text-center md:min-h-[90px] md:p-3">
            <p className="mb-0.5 text-[11px] text-gray-400 md:mb-1 md:text-sm">
              Average Hold Time
            </p>
            <p className="text-base font-semibold tabular-nums text-white md:text-xl">
              {formatDuration(stats.avgHoldSeconds)}
            </p>
            <p className="mt-1 text-[11px] text-gray-400">
              {stats.tradesWithDuration} trade
              {stats.tradesWithDuration === 1 ? "" : "s"} with duration
            </p>
          </div>

          <div>
            <p className="mb-1.5 text-[10px] font-medium uppercase tracking-wide text-gray-400 md:mb-2 md:text-xs">
              Hold Time Breakdown
            </p>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 md:gap-3">
              <div className="rounded-lg border border-white/10 bg-white/5 p-2.5 text-[11px] md:p-3 md:text-sm">
                <p className="text-gray-400">Winning Trades Avg Hold</p>
                <p className="mt-1 font-semibold tabular-nums text-green-400">
                  {formatDuration(stats.winningAvgHoldSeconds)}
                </p>
              </div>
              <div className="rounded-lg border border-white/10 bg-white/5 p-2.5 text-[11px] md:p-3 md:text-sm">
                <p className="text-gray-400">Losing Trades Avg Hold</p>
                <p className="mt-1 font-semibold tabular-nums text-red-400">
                  {formatDuration(stats.losingAvgHoldSeconds)}
                </p>
              </div>
            </div>
          </div>

          <div>
            <p className="mb-1.5 text-[10px] font-medium uppercase tracking-wide text-gray-400 md:mb-2 md:text-xs">
              Trade Duration Extremes
            </p>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 md:gap-3">
              <ExtremeRow
                label="Fastest Winner"
                extreme={stats.fastestWinner}
                pnlClass="text-green-400"
              />
              <ExtremeRow
                label="Longest Winner"
                extreme={stats.longestWinner}
                pnlClass="text-green-400"
              />
              <ExtremeRow
                label="Fastest Loser"
                extreme={stats.fastestLoser}
                pnlClass="text-red-400"
              />
              <ExtremeRow
                label="Longest Loser"
                extreme={stats.longestLoser}
                pnlClass="text-red-400"
              />
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
