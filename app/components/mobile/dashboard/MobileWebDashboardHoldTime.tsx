"use client"

import type { DurationExtreme, HoldTimeStats } from "@/lib/dashboardHoldTimeStats"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatHoldDurationSeconds } from "@/lib/tradeTimingDisplay"
import MobileWebDashboardEmptyCopy from "./MobileWebDashboardEmptyCopy"
import { mwDashMoneyClass, mwDashText } from "./mobileWebDashboardChrome"

function formatDuration(seconds: number | null | undefined) {
  if (seconds == null) return "—"
  return formatHoldDurationSeconds(Math.round(seconds)) ?? "—"
}

function StatCell({
  label,
  value,
  valueClass,
}: {
  label: string
  value: string
  valueClass?: string
}) {
  return (
    <div className="min-w-0 flex-1">
      <p className={`text-[11px] ${mwDashText.tertiary}`}>{label}</p>
      <p
        className={`mt-0.5 text-[13px] font-semibold tabular-nums ${
          valueClass ?? mwDashText.primary
        }`}
      >
        {value}
      </p>
    </div>
  )
}

function ExtremeCell({
  label,
  extreme,
}: {
  label: string
  extreme: DurationExtreme | null
}) {
  return (
    <div className="min-w-0">
      <p className={`text-[11px] ${mwDashText.tertiary}`}>{label}</p>
      {extreme ? (
        <>
          <p className={`mt-0.5 text-[13px] font-semibold tabular-nums ${mwDashText.primary}`}>
            {formatDuration(extreme.durationSeconds)}
          </p>
          <p
            className={`mt-0.5 text-[11px] font-medium tabular-nums ${mwDashMoneyClass(extreme.pnl)}`}
          >
            {formatCurrency(extreme.pnl)}
          </p>
        </>
      ) : (
        <p className={`mt-0.5 text-[13px] ${mwDashText.tertiary}`}>—</p>
      )}
    </div>
  )
}

export default function MobileWebDashboardHoldTime({
  stats,
  totalTrades = 0,
}: {
  stats: HoldTimeStats
  totalTrades?: number
}) {
  if (totalTrades === 0) {
    return (
      <MobileWebDashboardEmptyCopy body="Your hold time distribution will appear after more completed trades." />
    )
  }

  if (!stats.hasDurationData) {
    return (
      <MobileWebDashboardEmptyCopy
        title="Add entry and exit times"
        body="Hold time uses duration on completed trades."
      />
    )
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <p className={`text-[11px] ${mwDashText.tertiary}`}>Average hold time</p>
        <p className={`mt-1 text-[22px] font-semibold tabular-nums leading-none ${mwDashText.primary}`}>
          {formatDuration(stats.avgHoldSeconds)}
        </p>
        <p className={`mt-1 text-[11px] ${mwDashText.tertiary}`}>
          {stats.tradesWithDuration === 1
            ? "1 trade with duration"
            : `${stats.tradesWithDuration} trades with duration`}
        </p>
      </div>

      <div className="flex gap-4">
        <StatCell
          label="Winning hold"
          value={formatDuration(stats.winningAvgHoldSeconds)}
          valueClass={mwDashText.positive}
        />
        <div
          className="w-px self-stretch bg-[color:color-mix(in_srgb,var(--tt-text)_12%,transparent)]"
          aria-hidden
        />
        <StatCell
          label="Losing hold"
          value={formatDuration(stats.losingAvgHoldSeconds)}
          valueClass={mwDashText.negative}
        />
      </div>

      <div className="grid grid-cols-2 gap-x-4 gap-y-3">
        <ExtremeCell label="Fastest winner" extreme={stats.fastestWinner} />
        <ExtremeCell label="Longest winner" extreme={stats.longestWinner} />
        <ExtremeCell label="Fastest loser" extreme={stats.fastestLoser} />
        <ExtremeCell label="Longest loser" extreme={stats.longestLoser} />
      </div>
    </div>
  )
}
