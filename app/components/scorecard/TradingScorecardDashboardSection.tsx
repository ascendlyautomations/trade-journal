"use client"

import Link from "next/link"
import { reliabilityLabel } from "@/lib/scorecard"
import type { ScorecardCategoryResult, ScorecardResult } from "@/lib/scorecard"
import {
  scorecardBarFillClass,
  scorecardBarTrackClass,
  scorecardMetricClass,
  scorecardPanelClass,
  scorecardSubtitleClass,
  scorecardTitleClass,
} from "./scorecardStyles"

type TradingScorecardDashboardSectionProps = {
  result: ScorecardResult | null
  ready: boolean
  highlights: { strengths: string[]; weaknesses: string[] }
  onOpenDetail: () => void
  proFeatureUnlocked: boolean
}

function CategoryRow({ category }: { category: ScorecardCategoryResult }) {
  const scoreLabel =
    category.score != null ? String(category.score) : "—"
  return (
    <div className="space-y-1.5" data-testid={`scorecard.category.${category.id}`}>
      <div className="flex items-center justify-between gap-2 text-xs">
        <span className="font-medium text-gray-200">{category.title}</span>
        <span className="tabular-nums text-gray-400">
          {scoreLabel}
          <span className="text-gray-500"> · {category.coveragePercent}% cov</span>
        </span>
      </div>
      <div className={scorecardBarTrackClass}>
        <div
          className={scorecardBarFillClass(category.score)}
          style={{ width: category.score != null ? `${category.score}%` : "0%" }}
        />
      </div>
    </div>
  )
}

export default function TradingScorecardDashboardSection({
  result,
  ready,
  highlights,
  onOpenDetail,
  proFeatureUnlocked,
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
            <p className={scorecardMetricClass} data-testid="dashboard.scorecard.overall">
              {overallDisplay}
              <span className="ml-1 text-base font-semibold text-gray-400">/ 100</span>
            </p>
          ) : (
            <p className="text-lg font-semibold text-white" data-testid="dashboard.scorecard.building">
              Building your score
            </p>
          )}
          <p className="mt-1 text-xs text-gray-500">
            {result.overall.statusMessage} · {reliabilityLabel(result.overall.reliability)}
            {result.overall.contributions.length > 0 &&
            result.overall.nominalWeightIncluded < 0.999
              ? ` · ${result.overall.contributions.length}/4 categories`
              : ""}
          </p>
        </div>
        <p className="text-xs text-gray-500">
          {result.overall.tradeCount} trades · {result.overall.tradingDayCount} trading days
        </p>
      </div>

      <div className="mt-5 space-y-3">
        {result.categories.map((cat) => (
          <CategoryRow key={cat.id} category={cat} />
        ))}
      </div>

      {(highlights.strengths.length > 0 || highlights.weaknesses.length > 0) && (
        <div className="mt-4 grid gap-3 md:grid-cols-2">
          {highlights.strengths.length > 0 ? (
            <div>
              <p className="text-[10px] font-semibold uppercase tracking-wide text-emerald-400/90">
                Strengths
              </p>
              <ul className="mt-1 space-y-1 text-xs text-gray-300">
                {highlights.strengths.map((line) => (
                  <li key={line}>• {line}</li>
                ))}
              </ul>
            </div>
          ) : null}
          {highlights.weaknesses.length > 0 ? (
            <div>
              <p className="text-[10px] font-semibold uppercase tracking-wide text-amber-400/90">
                Focus areas
              </p>
              <ul className="mt-1 space-y-1 text-xs text-gray-300">
                {highlights.weaknesses.map((line) => (
                  <li key={line}>• {line}</li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>
      )}

      {!proFeatureUnlocked ? (
        <p className="mt-4 text-xs text-gray-500">
          TraxPro unlocks advanced psychology breakdowns on the{" "}
          <Link href="/psychology/analytics" className="text-blue-400 hover:underline">
            Psychology Analytics
          </Link>{" "}
          page.
        </p>
      ) : null}
    </section>
  )
}
