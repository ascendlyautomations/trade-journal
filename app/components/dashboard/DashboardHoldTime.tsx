"use client"

import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import {
  DASHBOARD_MOBILE_CARD_PAD_CLASS,
  DASHBOARD_MOBILE_CARD_TITLE_CLASS,
} from "@/app/components/dashboard/dashboardMobileUi"
import {
  dashboardMobileHelperClass,
  dashboardMobileNestedLabelClass,
} from "@/app/components/dashboard/dashboardInsightStyles"
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

function MobileExtremeCell({
  label,
  extreme,
  pnlClass,
}: ExtremeRowProps) {
  return (
    <div className="rounded-lg border border-white/10 bg-white/5 px-2.5 py-2 text-center">
      <p className={dashboardMobileNestedLabelClass}>{label}</p>
      {extreme ? (
        <>
          <p className="mt-0.5 text-[11px] font-semibold tabular-nums text-white">
            {formatDuration(extreme.durationSeconds)}
          </p>
          <p className={`mt-0.5 text-[10px] font-medium tabular-nums ${pnlClass}`}>
            {formatCurrency(extreme.pnl)}
          </p>
        </>
      ) : (
        <p className={`mt-0.5 ${dashboardMobileHelperClass}`}>—</p>
      )}
    </div>
  )
}

/** Mobile-only compact hold-time layout. */
function MobileHoldTimeCompact({ stats }: { stats: HoldTimeStats }) {
  return (
    <div className="space-y-2">
      <div className="rounded-lg border border-white/10 bg-white/5 px-2.5 py-2 text-center">
        <p className={dashboardMobileNestedLabelClass}>Average Hold Time</p>
        <p className="mt-0.5 text-sm font-semibold tabular-nums text-white">
          {formatDuration(stats.avgHoldSeconds)}
        </p>
        <p className={`mt-0.5 ${dashboardMobileHelperClass}`}>
          {stats.tradesWithDuration} trade
          {stats.tradesWithDuration === 1 ? "" : "s"} with duration
        </p>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <div className="rounded-lg border border-white/10 bg-white/5 px-2.5 py-2 text-center">
          <p className={dashboardMobileNestedLabelClass}>Winning Hold</p>
          <p className="mt-0.5 text-[11px] font-semibold tabular-nums text-green-400">
            {formatDuration(stats.winningAvgHoldSeconds)}
          </p>
        </div>
        <div className="rounded-lg border border-white/10 bg-white/5 px-2.5 py-2 text-center">
          <p className={dashboardMobileNestedLabelClass}>Losing Hold</p>
          <p className="mt-0.5 text-[11px] font-semibold tabular-nums text-red-400">
            {formatDuration(stats.losingAvgHoldSeconds)}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <MobileExtremeCell
          label="Fastest Winner"
          extreme={stats.fastestWinner}
          pnlClass="text-green-400"
        />
        <MobileExtremeCell
          label="Longest Winner"
          extreme={stats.longestWinner}
          pnlClass="text-green-400"
        />
        <MobileExtremeCell
          label="Fastest Loser"
          extreme={stats.fastestLoser}
          pnlClass="text-red-400"
        />
        <MobileExtremeCell
          label="Longest Loser"
          extreme={stats.longestLoser}
          pnlClass="text-red-400"
        />
      </div>
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
    <div
      className={`flex h-full min-h-[180px] flex-col rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md max-md:h-auto max-md:min-h-0 md:min-h-[200px] md:p-4 ${DASHBOARD_MOBILE_CARD_PAD_CLASS}`}
    >
      <h2
        className={`mb-2 text-xs font-semibold text-blue-300 md:mb-3 md:text-base ${DASHBOARD_MOBILE_CARD_TITLE_CLASS}`}
      >
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
        <>
          <div className="md:hidden">
            <MobileHoldTimeCompact stats={stats} />
          </div>
          <div className="hidden space-y-3 md:block md:space-y-4">
            <div className="flex min-h-[90px] flex-col items-center justify-center rounded-xl border border-white/10 bg-white/5 p-3 text-center">
              <p className="mb-1 text-sm text-gray-400">Average Hold Time</p>
              <p className="text-xl font-semibold tabular-nums text-white">
                {formatDuration(stats.avgHoldSeconds)}
              </p>
              <p className="mt-1 text-[11px] text-gray-400">
                {stats.tradesWithDuration} trade
                {stats.tradesWithDuration === 1 ? "" : "s"} with duration
              </p>
            </div>

            <div>
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">
                Hold Time Breakdown
              </p>
              <div className="grid grid-cols-2 gap-3">
                <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-sm">
                  <p className="text-gray-400">Winning Trades Avg Hold</p>
                  <p className="mt-1 font-semibold tabular-nums text-green-400">
                    {formatDuration(stats.winningAvgHoldSeconds)}
                  </p>
                </div>
                <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-sm">
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
              <div className="grid grid-cols-2 gap-3">
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
        </>
      )}
    </div>
  )
}
