"use client"

import Link from "next/link"
import { useMemo, useState } from "react"
import type { TradingRulesComplianceAnalytics } from "@/lib/analytics/tradingRulesComplianceAnalytics"
import { dashboardInsightCardClass } from "@/app/components/dashboard/dashboardInsightStyles"

type Props = {
  analytics: TradingRulesComplianceAnalytics | null
  loading?: boolean
  error?: string | null
  onOpenTrade?: (tradeId: string) => void
  compact?: boolean
}

const cardClass =
  "rounded-xl border border-white/10 bg-white/5 p-4 max-md:p-3"

function TrendBars({
  points,
  mode,
}: {
  points: TradingRulesComplianceAnalytics["weeklyTrend"]
  mode: "weekly" | "monthly"
}) {
  const [expanded, setExpanded] = useState(false)
  const visible = expanded ? points : points.slice(-6)
  if (points.length === 0) {
    return (
      <p className="text-xs text-gray-500">
        No evaluable rule checks in this scope yet.
      </p>
    )
  }
  return (
    <div className="space-y-2">
      <div className="space-y-2">
        {visible.map((row) => (
          <div key={`${mode}-${row.key}`} className="space-y-1">
            <div className="flex items-center justify-between gap-2 text-xs">
              <span className="text-gray-400">{row.label}</span>
              <span className="tabular-nums text-gray-300">
                {row.insufficientData
                  ? "Insufficient data"
                  : row.adherencePercent != null
                    ? `${row.adherencePercent}%`
                    : "—"}
              </span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
              <div
                className="h-full rounded-full bg-emerald-400/80"
                style={{
                  width: `${Math.min(100, Math.max(0, row.adherencePercent ?? 0))}%`,
                }}
              />
            </div>
            <p className="text-[10px] text-gray-500">
              {row.evaluated} evaluated · {row.violations} violations
              {row.coverageNote ? ` · ${row.coverageNote}` : ""}
            </p>
          </div>
        ))}
      </div>
      {points.length > 6 ? (
        <button
          type="button"
          className="text-xs font-medium text-blue-400 hover:text-blue-300"
          onClick={() => setExpanded((v) => !v)}
        >
          {expanded ? "Show recent only" : `Show all ${points.length} periods`}
        </button>
      ) : null}
    </div>
  )
}

export default function TradingRulesCompliancePanel({
  analytics,
  loading,
  error,
  onOpenTrade,
  compact = false,
}: Props) {
  const [impactOpen, setImpactOpen] = useState(false)
  const [timelineOpen, setTimelineOpen] = useState(false)
  const impactReady = useMemo(
    () => analytics?.impacts.filter((row) => row.sufficientSample) ?? [],
    [analytics]
  )

  if (loading) {
    return (
      <div className={cardClass}>
        <p className="text-sm text-gray-400">Loading trading rules analytics…</p>
      </div>
    )
  }

  if (error) {
    return (
      <div className={cardClass}>
        <p className="text-sm text-red-400">{error}</p>
      </div>
    )
  }

  if (!analytics || analytics.score.evaluated === 0) {
    return (
      <div className={cardClass}>
        <p className="text-sm font-medium text-white">Trading rules</p>
        <p className="mt-1 text-xs text-gray-400">
          Configure rules in Settings and log trades with the data each rule needs.
          Missing fields stay unevaluated — not counted as compliant.
        </p>
        <Link
          href="/settings"
          className="mt-3 inline-block text-xs font-semibold text-blue-400"
        >
          Open Trading Rules
        </Link>
      </div>
    )
  }

  const { score } = analytics

  return (
    <section className="space-y-3" data-testid="tradingRules.compliancePanel">
      <div className={`${cardClass} ${dashboardInsightCardClass}`}>
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-wide text-blue-300">
              Compliance score
            </p>
            <p className="mt-1 text-3xl font-semibold tabular-nums text-white">
              {score.adherencePercent != null ? `${score.adherencePercent}%` : "—"}
            </p>
          </div>
          <MotionStats score={score} />
        </div>
        <p className="mt-3 text-xs leading-relaxed text-gray-400">
          {score.explanation}
          {analytics.usesHistoricalRevisions
            ? " Rules active when each trade occurred use your saved revisions."
            : ""}
        </p>
      </div>

      {!compact ? (
        <>
          <div className={cardClass}>
            <button
              type="button"
              className="flex w-full items-center justify-between text-left"
              onClick={() => setImpactOpen((v) => !v)}
            >
              <span className="text-sm font-semibold text-white">
                Rule impact analysis
              </span>
              <span className="text-xs text-gray-400">
                {impactOpen ? "Hide" : "Show"}
              </span>
            </button>
            {impactOpen ? (
              <div className="mt-3 space-y-2">
                <p className="text-xs text-gray-500">
                  Compares priced trades when a rule was followed vs violated (≥5
                  priced per side). Correlations only — not causal claims.
                </p>
                {impactReady.length === 0 ? (
                  <p className="text-xs text-gray-500">
                    Not enough priced trades in both groups yet.
                  </p>
                ) : (
                  impactReady.map((row) => (
                    <article
                      key={row.ruleId}
                      className="rounded-lg border border-white/10 bg-black/20 p-3"
                    >
                      <p className="text-xs font-semibold text-white">
                        {row.ruleLabel}
                      </p>
                      {row.summary ? (
                        <p className="mt-1 text-xs leading-relaxed text-gray-400">
                          {row.summary}
                        </p>
                      ) : null}
                    </article>
                  ))
                )}
              </div>
            ) : null}
          </div>

          <div className={cardClass}>
            <button
              type="button"
              className="flex w-full items-center justify-between text-left"
              onClick={() => setTimelineOpen((v) => !v)}
            >
              <span className="text-sm font-semibold text-white">
                Violation timeline
              </span>
              <span className="text-xs text-gray-400">
                {analytics.violations.length} events
              </span>
            </button>
            {timelineOpen ? (
              <ul className="mt-3 max-h-64 space-y-2 overflow-y-auto">
                {analytics.violations.length === 0 ? (
                  <li className="text-xs text-gray-500">No violations recorded.</li>
                ) : (
                  analytics.violations.slice(0, 40).map((event) => (
                    <li
                      key={event.id}
                      className="rounded-lg border border-white/10 px-3 py-2 text-xs"
                    >
                      <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                        <span className="font-medium text-white">
                          {event.ruleLabel}
                        </span>
                        <span className="text-gray-500">
                          {event.dayKey}
                          {event.level !== "trade"
                            ? ` · ${event.level} limit`
                            : ""}
                          {event.scopeLabel ? ` · ${event.scopeLabel}` : ""}
                        </span>
                      </div>
                      <p className="mt-1 text-gray-400">{event.summary}</p>
                      {event.accountLabel ? (
                        <p className="mt-0.5 text-[10px] text-gray-500">
                          Account: {event.accountLabel}
                        </p>
                      ) : null}
                      {event.tradeId && onOpenTrade ? (
                        <button
                          type="button"
                          className="mt-1 font-medium text-blue-400 hover:text-blue-300"
                          onClick={() => onOpenTrade(event.tradeId!)}
                        >
                          Open trade
                        </button>
                      ) : event.tradeId ? (
                        <Link
                          href={`/trade/${event.tradeId}`}
                          className="mt-1 inline-block font-medium text-blue-400"
                        >
                          Open trade
                        </Link>
                      ) : null}
                    </li>
                  ))
                )}
              </ul>
            ) : null}
          </div>

          <div className={`${cardClass} grid gap-4 md:grid-cols-2`}>
            <div>
              <p className="text-sm font-semibold text-white">Weekly trend</p>
              <div className="mt-2">
                <TrendBars points={analytics.weeklyTrend} mode="weekly" />
              </div>
            </div>
            <div>
              <p className="text-sm font-semibold text-white">Monthly trend</p>
              <div className="mt-2">
                <TrendBars points={analytics.monthlyTrend} mode="monthly" />
              </div>
            </div>
          </div>
        </>
      ) : null}
    </section>
  )
}

function MotionStats({ score }: { score: TradingRulesComplianceAnalytics["score"] }) {
  return (
    <dl className="grid grid-cols-3 gap-3 text-center text-xs">
      <div>
        <dt className="text-gray-500">Followed</dt>
        <dd className="mt-0.5 font-semibold tabular-nums text-emerald-400">
          {score.followed}
        </dd>
      </div>
      <div>
        <dt className="text-gray-500">Violations</dt>
        <dd className="mt-0.5 font-semibold tabular-nums text-red-400">
          {score.violated}
        </dd>
      </div>
      <div>
        <dt className="text-gray-500">Unevaluated</dt>
        <dd className="mt-0.5 font-semibold tabular-nums text-gray-300">
          {score.unevaluated}
        </dd>
      </div>
    </dl>
  )
}
