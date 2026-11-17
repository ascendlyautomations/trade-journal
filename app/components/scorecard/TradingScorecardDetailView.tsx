"use client"

import type { ScorecardAdherenceReadout, ScorecardResult } from "@/lib/scorecard"
import { scorecardDisplayProse } from "./scorecardDisplay"
import { scorecardPanelClass, scorecardSubtitleClass, scorecardTitleClass } from "./scorecardStyles"

type TradingScorecardDetailViewProps = {
  result: ScorecardResult
  proFeatureUnlocked: boolean
}

function AdherenceRow({ row }: { row: ScorecardAdherenceReadout }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <div>
        <p className="text-sm font-medium text-white">{row.label}</p>
        {row.sample ? <p className="text-xs text-gray-500">{row.sample}</p> : null}
      </div>
      <p className="text-sm tabular-nums text-blue-300">{row.value ?? row.pending}</p>
    </div>
  )
}

export default function TradingScorecardDetailView({
  result,
}: TradingScorecardDetailViewProps) {
  const overall =
    result.overall.status === "ready" && result.overall.score != null
      ? result.overall.score
      : null

  return (
    <div className="space-y-6" data-testid="scorecard.detail">
      <header className={scorecardPanelClass}>
        <p className="text-xs text-gray-500">Scope</p>
        <h1 className="mt-1 text-xl font-semibold text-white">Trading Scorecard</h1>
        <p className={`mt-1 ${scorecardSubtitleClass}`}>{result.scopeLabel}</p>
        <div className="mt-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
            Plan-Adherence Score
          </p>
          {overall != null ? (
            <p className="mt-1 text-4xl font-bold tabular-nums text-white">
              {overall}
              <span className="text-lg text-gray-400"> / 100</span>
            </p>
          ) : (
            <p className="mt-1 text-lg font-semibold text-white">Building</p>
          )}
          <p className="mt-2 text-sm text-gray-400">
            {scorecardDisplayProse(result.overall.statusMessage)}
          </p>
          <p className="mt-1 text-xs text-gray-500">
            {result.overall.tradeCount} trades · {result.overall.tradingDayCount} trading days
          </p>
        </div>
      </header>

      <section className={`${scorecardPanelClass} space-y-3`}>
        <h2 className={scorecardTitleClass}>Adherence</h2>
        {result.adherence.map((row) => (
          <AdherenceRow key={row.id} row={row} />
        ))}
      </section>

      {result.insights.length > 0 ? (
        <section className={scorecardPanelClass}>
          <h2 className={scorecardTitleClass}>Insights</h2>
          <ul className="mt-3 space-y-2">
            {result.insights.map((insight) => (
              <li key={insight.id} className="text-sm text-gray-300">
                {scorecardDisplayProse(insight.text)}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  )
}
