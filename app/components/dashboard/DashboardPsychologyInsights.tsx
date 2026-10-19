"use client"

import { useMemo } from "react"
import { useRecentDailyCheckIns } from "@/lib/dailyCheckIn/useRecentDailyCheckIns"
import {
  formatHours,
  formatRatingOutOfFive,
  stressAverageDisplayText,
} from "@/lib/psychology/display"
import { buildDashboardPsychologyStats } from "@/lib/psychology/dashboardStats"
import {
  displayCheckInDayCountForGate,
  displayTradeCountForGate,
  PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT,
} from "@/lib/psychology/unlockProgress"
import type { DashboardTradeRow } from "./dashboardTypes"

type DashboardPsychologyInsightsProps = {
  userId: string
  trades: DashboardTradeRow[]
  /** False while Dashboard trades have not been hydrated — avoids a 0/5 flash. */
  tradesReady?: boolean
}

function MetricCell({
  label,
  value,
}: {
  label: string
  value: string
}) {
  return (
    <div className="tt-dash-psych-metric min-w-0 rounded-lg border border-white/10 bg-white/5 px-3 py-2">
      <p className="text-[11px] font-medium uppercase tracking-wide text-gray-400">
        {label}
      </p>
      <p className="mt-0.5 text-sm font-semibold tabular-nums text-white">
        {value}
      </p>
    </div>
  )
}

export function DashboardPsychologyInsightsSkeleton() {
  return (
    <div
      className="tt-dash-psych tt-dash-checkin h-[5.5rem] animate-pulse rounded-xl border border-white/10 bg-white/5"
      aria-hidden
    />
  )
}

export default function DashboardPsychologyInsights({
  userId,
  trades,
  tradesReady = true,
}: DashboardPsychologyInsightsProps) {
  const { checkIns, isReady, loadError, refresh } = useRecentDailyCheckIns(userId)

  const stats = useMemo(
    () => buildDashboardPsychologyStats(trades, checkIns),
    [trades, checkIns]
  )

  if (!isReady || !tradesReady) {
    return <DashboardPsychologyInsightsSkeleton />
  }

  const { unlock, summary, showMetrics } = stats

  return (
    <section
      className="tt-dash-psych tt-dash-checkin rounded-xl border border-white/10 bg-white/5 px-3.5 py-3 backdrop-blur-md md:px-4"
      data-testid="dashboard.psychologyInsights"
    >
      <div className="min-w-0">
        <h2 className="text-sm font-semibold text-white">Psychology Insights</h2>
        <p className="text-xs text-gray-400">
          Patterns from your trades and daily check-ins
        </p>
      </div>

      {loadError && checkIns.length === 0 ? (
        <p className="mt-2 text-xs text-red-400">
          {loadError}{" "}
          <button type="button" className="underline" onClick={() => void refresh()}>
            Retry
          </button>
        </p>
      ) : showMetrics ? (
        <div className="mt-2.5 grid grid-cols-2 gap-2 md:grid-cols-4">
          <MetricCell label="Check-ins" value={String(summary.checkInCount)} />
          {summary.averageSleepHours != null ? (
            <MetricCell
              label="Avg Sleep"
              value={formatHours(summary.averageSleepHours)}
            />
          ) : null}
          {summary.averageFocus != null ? (
            <MetricCell
              label="Avg Focus"
              value={formatRatingOutOfFive(summary.averageFocus)}
            />
          ) : null}
          {summary.averageStress != null ? (
            <MetricCell
              label="Avg Stress"
              value={stressAverageDisplayText(summary.averageStress)}
            />
          ) : null}
        </div>
      ) : (
        <div
          className="mt-2.5"
          data-testid="dashboard.psychologyInsights.requirements"
        >
          <h3 className="text-sm font-semibold text-white">
            5 Daily Check-Ins &amp; 5 Trades Required
          </h3>
          <p className="mt-0.5 text-xs text-gray-400">
            Log check-ins and trade psychology to unlock insights.
          </p>
          <p className="mt-1.5 text-xs tabular-nums text-gray-300">
            Check-in days {displayCheckInDayCountForGate(unlock)}/
            {PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT}
            {" · "}
            Trades {displayTradeCountForGate(unlock)}/
            {PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT}
          </p>
        </div>
      )}
    </section>
  )
}
