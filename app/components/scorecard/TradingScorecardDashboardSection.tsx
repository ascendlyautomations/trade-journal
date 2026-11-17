"use client"

import type { ScorecardResult } from "@/lib/scorecard"
import { scorecardDisplayProse } from "./scorecardDisplay"
import {
  scorecardMetricClass,
  scorecardPanelClass,
  scorecardSubtitleClass,
  scorecardTitleClass,
} from "./scorecardStyles"

type TradingScorecardDashboardSectionProps = {
  result: ScorecardResult | null
  ready: boolean
  onOpenDetail: () => void
}

export default function TradingScorecardDashboardSection({
  result,
  ready,
  onOpenDetail,
}: TradingScorecardDashboardSectionProps) {
  if (!ready) {
    return (
      <section
        className={`${scorecardPanelClass} animate-pulse`}
        data-testid="dashboard.scorecard.loading"
        aria-hidden
      >
        <div className="h-24 rounded-lg bg-white/5" />
      </section>
    )
  }

  if (!result) {
    return (
      <section className={scorecardPanelClass} data-testid="dashboard.scorecard.empty">
        <h2 className={scorecardTitleClass}>Trading Scorecard</h2>
        <p className={`mt-1 ${scorecardSubtitleClass}`}>
          Log trades in this dashboard scope to start building your score.
        </p>
      </section>
    )
  }

  const overallDisplay =
    result.overall.status === "ready" && result.overall.score != null
      ? result.overall.score
      : null

  return (
    <section className={scorecardPanelClass} data-testid="dashboard.scorecard">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className={scorecardTitleClass}>Trading Scorecard</h2>
          <p className={`mt-0.5 ${scorecardSubtitleClass}`}>{result.scopeLabel}</p>
        </div>
        <button
          type="button"
          onClick={onOpenDetail}
          className="shrink-0 text-xs font-semibold text-blue-400 hover:text-blue-300"
          data-testid="dashboard.scorecard.viewDetail"
        >
          View breakdown
        </button>
      </div>

      <div className="mt-4 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          {overallDisplay != null ? (
            <>
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                Plan-Adherence Score
              </p>
              <p className={scorecardMetricClass} data-testid="dashboard.scorecard.overall">
                {overallDisplay}
                <span className="ml-1 text-base font-semibold text-gray-400">/ 100</span>
              </p>
            </>
          ) : (
            <p className="text-lg font-semibold text-white" data-testid="dashboard.scorecard.building">
              Building
            </p>
          )}
          <p className="mt-1 text-xs text-gray-500">
            {scorecardDisplayProse(result.overall.statusMessage)}
          </p>
        </div>
        <p className="text-xs text-gray-500">
          {result.overall.tradeCount} trades · {result.overall.tradingDayCount} trading days
        </p>
      </div>

      <div className="mt-4 space-y-2">
        {result.adherence.map((row) => (
          <div key={row.id} className="flex items-baseline justify-between gap-3 text-xs">
            <span className="text-gray-300">{row.label}</span>
            <span className="tabular-nums text-gray-100">{row.value ?? row.pending}</span>
          </div>
        ))}
      </div>

      {result.insights.length > 0 ? (
        <ul className="mt-4 space-y-1 text-xs text-gray-300">
          {result.insights.map((insight) => (
            <li key={insight.id}>{scorecardDisplayProse(insight.text)}</li>
          ))}
        </ul>
      ) : null}
    </section>
  )
}
