"use client"

import Link from "next/link"
import { useState } from "react"
import { reliabilityLabel } from "@/lib/scorecard"
import type { ScorecardCategoryResult, ScorecardResult } from "@/lib/scorecard"
import {
  categoryPhase1DetailScoreLabel,
  PHASE1_SCORE_EXPLAINER,
  PLAN_ADHERENCE_SCORE_LABEL,
  scorecardDisplayProse,
} from "./scorecardDisplay"
import {
  scorecardBarFillClass,
  scorecardBarTrackClass,
  scorecardPanelClass,
  scorecardSubtitleClass,
  scorecardTitleClass,
} from "./scorecardStyles"

type TradingScorecardDetailViewProps = {
  result: ScorecardResult
  proFeatureUnlocked: boolean
}

function CategorySection({
  category,
  proFeatureUnlocked,
}: {
  category: ScorecardCategoryResult
  proFeatureUnlocked: boolean
}) {
  const [open, setOpen] = useState(false)
  const metricsHeading =
    category.id === "psychology"
      ? "Insights & coverage"
      : category.id === "risk"
        ? "Metrics & coverage"
        : "Contributing metrics"

  return (
    <section
      className={scorecardPanelClass}
      data-testid={`scorecard.detail.${category.id}`}
    >
      <button
        type="button"
        className="flex w-full items-start justify-between gap-3 text-left"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
      >
        <div>
          <h3 className={scorecardTitleClass}>{category.title}</h3>
          <p className={scorecardSubtitleClass}>
            Nominal weight {(category.weight * 100).toFixed(0)}% ·{" "}
            {categoryPhase1DetailScoreLabel(category)} ·{" "}
            {reliabilityLabel(category.reliability)} · {category.coveragePercent}% coverage
          </p>
        </div>
        <span className="text-sm text-blue-400">{open ? "Hide" : "Show"}</span>
      </button>

      {open ? (
        <div className="mt-4 space-y-4 border-t border-white/10 pt-4">
          <div className={scorecardBarTrackClass}>
            <div
              className={scorecardBarFillClass(category.score)}
              style={{
                width: category.score != null ? `${category.score}%` : "0%",
              }}
            />
          </div>

          {category.subMetrics.length > 0 ? (
            <div>
              <h4 className="text-xs font-semibold uppercase tracking-wide text-gray-500">
                {metricsHeading}
              </h4>
              <ul className="mt-2 space-y-3">
                {category.subMetrics.map((metric) => (
                  <li
                    key={metric.id}
                    className="rounded-lg border border-white/10 bg-black/20 p-3"
                  >
                    <div className="flex flex-wrap items-baseline justify-between gap-2">
                      <span className="text-sm font-medium text-white">{metric.label}</span>
                      <span className="text-sm tabular-nums text-blue-300">{metric.value}</span>
                    </div>
                    <p className="mt-1 text-xs text-gray-400">{metric.explanation}</p>
                    <p className="mt-1 text-[10px] text-gray-500">
                      {metric.sampleSize} {metric.sampleLabel}
                    </p>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}

          {category.strengths.length > 0 ? (
            <div>
              <h4 className="text-xs font-semibold uppercase tracking-wide text-emerald-400/90">
                Strengths
              </h4>
              <ul className="mt-1 list-inside list-disc text-sm text-gray-300">
                {category.strengths.map((s) => (
                  <li key={s}>{scorecardDisplayProse(s)}</li>
                ))}
              </ul>
            </div>
          ) : null}

          {category.weaknesses.length > 0 ? (
            <div>
              <h4 className="text-xs font-semibold uppercase tracking-wide text-amber-400/90">
                Opportunities
              </h4>
              <ul className="mt-1 list-inside list-disc text-sm text-gray-300">
                {category.weaknesses.map((w) => (
                  <li key={w}>{scorecardDisplayProse(w)}</li>
                ))}
              </ul>
            </div>
          ) : null}

          {category.dataGaps.length > 0 ? (
            <div>
              <h4 className="text-xs font-semibold uppercase tracking-wide text-gray-500">
                Data to log next
              </h4>
              <ul className="mt-1 list-inside list-disc text-sm text-gray-400">
                {category.dataGaps.map((g) => (
                  <li key={g}>{scorecardDisplayProse(g)}</li>
                ))}
              </ul>
            </div>
          ) : null}

          {category.id === "psychology" && !proFeatureUnlocked ? (
            <p className="text-xs text-gray-500">
              TraxPro unlocks deeper trend reports and advanced filters on{" "}
              <Link href="/psychology/analytics" className="text-blue-400 hover:underline">
                Psychology Analytics
              </Link>
              . Scorecard insights above remain available on Free.
            </p>
          ) : null}

          <div className="flex flex-wrap gap-3 text-xs font-semibold">
            <Link href="/trades" className="text-blue-400 hover:underline">
              Review trades
            </Link>
            {category.id === "psychology" ? (
              <Link href="/psychology/analytics" className="text-blue-400 hover:underline">
                Psychology Analytics
              </Link>
            ) : null}
          </div>
        </div>
      ) : null}
    </section>
  )
}

export default function TradingScorecardDetailView({
  result,
  proFeatureUnlocked,
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
          {overall != null ? (
            <>
              <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
                {PLAN_ADHERENCE_SCORE_LABEL}
              </p>
              <p className="mt-1 text-4xl font-bold tabular-nums text-white">
                {overall}
                <span className="text-lg text-gray-400"> / 100</span>
              </p>
            </>
          ) : (
            <p className="text-lg font-semibold text-white">Building your score</p>
          )}
          <p className="mt-2 text-sm text-gray-400">
            {scorecardDisplayProse(result.overall.statusMessage)}
          </p>
          <p className="mt-2 text-xs leading-relaxed text-gray-500">{PHASE1_SCORE_EXPLAINER}</p>
          <p className="mt-1 text-xs text-gray-500">
            {result.overall.tradeCount} trades · {result.overall.tradingDayCount} trading days ·{" "}
            {reliabilityLabel(result.overall.reliability)} · {result.overall.coveragePercent}%
            coverage
          </p>
          {result.overall.contributions.length > 0 ? (
            <div className="mt-3 rounded-lg border border-white/10 bg-black/20 p-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                Categories in this {PLAN_ADHERENCE_SCORE_LABEL}
              </p>
              <ul className="mt-2 space-y-1 text-xs text-gray-300">
                {result.overall.contributions.map((row) => (
                  <li key={row.id} className="flex flex-wrap justify-between gap-2">
                    <span>
                      {row.title}: {row.score}/100
                    </span>
                    <span className="tabular-nums text-gray-500">
                      {(row.nominalWeight * 100).toFixed(0)}% nominal ·{" "}
                      {(row.effectiveWeight * 100).toFixed(0)}% effective
                    </span>
                  </li>
                ))}
              </ul>
              {result.overall.nominalWeightIncluded < 0.999 ? (
                <p className="mt-2 text-[11px] text-amber-200/90">
                  Partial composite ({Math.round(result.overall.nominalWeightIncluded * 100)}% of
                  nominal weight), missing categories are excluded, not treated as zero
                  performance.
                </p>
              ) : null}
            </div>
          ) : null}
        </div>
        <p className="mt-4 text-xs text-gray-500">
          Not investment advice. Psychology patterns are correlational, not causal.
        </p>
      </header>

      {result.categories.map((category) => (
        <CategorySection
          key={category.id}
          category={category}
          proFeatureUnlocked={proFeatureUnlocked}
        />
      ))}
    </div>
  )
}
