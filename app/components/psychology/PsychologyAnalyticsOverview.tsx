"use client"

import { buildDashboardPsychologyStats } from "@/lib/psychology/dashboardStats"
import {
  formatPsychologyMoney,
  formatPsychologyWinRate,
} from "@/lib/psychology/reports/format"
import type { PsychologyAnalyticsReport } from "@/lib/psychology/reports/types"
import type { TraderDailyCheckIn } from "@/lib/dailyCheckIn/types"
import type { PsychologyReportTrade } from "@/lib/psychology/reports/types"
import { psychologyAnalyticsOverviewCounts } from "@/lib/psychology/psychologyProgressMessaging"
import { stressAverageDisplayText } from "@/lib/psychology/display"

type PsychologyAnalyticsOverviewProps = {
  report: PsychologyAnalyticsReport
  journalTrades: readonly PsychologyReportTrade[]
  checkIns: readonly TraderDailyCheckIn[]
  scopeLabel?: string | null
}

export default function PsychologyAnalyticsOverview({
  report,
  journalTrades,
  checkIns,
  scopeLabel,
}: PsychologyAnalyticsOverviewProps) {
  const counts = psychologyAnalyticsOverviewCounts(report, journalTrades, checkIns)
  const { summary, showMetrics } = buildDashboardPsychologyStats(journalTrades, checkIns)
  const baseline = report.baseline

  return (
    <section className="space-y-3" data-testid="psychologyAnalytics.overview">
      <div>
        <h2 className="text-base font-semibold text-white">Overview</h2>
        {scopeLabel ? (
          <p className="text-xs text-gray-500">Trade scope: {scopeLabel}</p>
        ) : (
          <p className="text-xs text-gray-500">
            Counts use the same trade scope as your Dashboard when you open analytics from
            there.
          </p>
        )}
      </div>

      <div className="grid grid-cols-3 gap-2">
        <CountTile label="Check-in days" value={counts.checkInPsychDays} />
        <CountTile label="Qualifying trades" value={counts.scopedTradeCount} />
        <CountTile label="Matched days" value={counts.matchedTradeCount} />
      </div>

      {showMetrics ? (
        <div className="rounded-xl border border-white/10 bg-white/5 p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
            Your trades in this scope
          </p>
          <div className="mt-3 flex flex-wrap gap-6 text-sm">
            <div>
              <p className="text-[10px] uppercase text-gray-500">Win rate</p>
              <p className="font-semibold tabular-nums text-white">
                {formatPsychologyWinRate(baseline.winRate)}
              </p>
            </div>
            <div>
              <p className="text-[10px] uppercase text-gray-500">Avg P&L / trade</p>
              <p className="font-semibold tabular-nums text-white">
                {formatPsychologyMoney(baseline.averagePnL ?? 0)}
              </p>
            </div>
            <div>
              <p className="text-[10px] uppercase text-gray-500">Expected $ / trade</p>
              <p className="font-semibold tabular-nums text-white">
                {formatPsychologyMoney(baseline.expectancy ?? 0)}
              </p>
            </div>
          </div>
        </div>
      ) : null}

      {showMetrics && summary.checkInCount > 0 ? (
        <div className="rounded-xl border border-white/10 bg-white/5 p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
            Check-in trends (matched trading days · {summary.checkInCount})
          </p>
          <div className="mt-3 grid grid-cols-2 gap-3 text-xs text-gray-300">
            {summary.averageSleepHours != null ? (
              <TrendRow label="Avg sleep" value={`${summary.averageSleepHours.toFixed(1)} h`} />
            ) : null}
            {summary.averageMorningRating != null ? (
              <TrendRow
                label="Morning rating"
                value={summary.averageMorningRating.toFixed(1)}
              />
            ) : null}
            {summary.averageStress != null ? (
              <TrendRow
                label="Stress"
                value={stressAverageDisplayText(summary.averageStress)}
              />
            ) : null}
            {summary.averageEnergy != null ? (
              <TrendRow label="Energy" value={summary.averageEnergy.toFixed(1)} />
            ) : null}
          </div>
        </div>
      ) : null}
    </section>
  )
}

function CountTile({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-lg border border-white/10 bg-white/5 px-2 py-3 text-center">
      <p className="text-lg font-semibold tabular-nums text-white">{value}</p>
      <p className="mt-0.5 text-[10px] leading-tight text-gray-500">{label}</p>
    </div>
  )
}

function TrendRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-[10px] uppercase text-gray-500">{label}</p>
      <p className="font-medium tabular-nums text-white">{value}</p>
    </div>
  )
}
