"use client"

import EmptyState from "@/app/components/ui/EmptyState"
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
    <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-xs md:text-sm">
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
        <p className="text-gray-500">No matching trades</p>
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
    <div className="flex min-h-[200px] h-full flex-col rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
      <h2 className="mb-3 text-sm md:text-base font-semibold text-blue-300">
        Hold Time
      </h2>

      {showEmpty ? (
        <EmptyState
          title="Not Enough Data Yet"
          description="Add more trades to unlock detailed analytics."
          className="py-8"
        />
      ) : !stats.hasDurationData ? (
        <EmptyState
          title="No duration data"
          description="Add duration_seconds or entry/exit times to unlock hold time analytics."
          className="py-8"
        />
      ) : (
        <div className="space-y-4">
          <div className="flex min-h-[90px] flex-col items-center justify-center rounded-xl border border-white/10 bg-white/5 p-3 text-center">
            <p className="mb-1 text-xs md:text-sm text-gray-400">
              Average Hold Time
            </p>
            <p className="text-lg md:text-xl font-semibold tabular-nums text-white">
              {formatDuration(stats.avgHoldSeconds)}
            </p>
            <p className="mt-1 text-[11px] text-gray-500">
              {stats.tradesWithDuration} trade
              {stats.tradesWithDuration === 1 ? "" : "s"} with duration
            </p>
          </div>

          <div>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">
              Hold Time Breakdown
            </p>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-xs md:text-sm">
                <p className="text-gray-400">Winning Trades Avg Hold</p>
                <p className="mt-1 font-semibold tabular-nums text-green-400">
                  {formatDuration(stats.winningAvgHoldSeconds)}
                </p>
              </div>
              <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-xs md:text-sm">
                <p className="text-gray-400">Losing Trades Avg Hold</p>
                <p className="mt-1 font-semibold tabular-nums text-red-400">
                  {formatDuration(stats.losingAvgHoldSeconds)}
                </p>
              </div>
            </div>
          </div>

          <div>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">
              Trade Duration Extremes
            </p>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
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
