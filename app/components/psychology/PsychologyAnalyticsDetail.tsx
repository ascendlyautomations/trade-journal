"use client"

import { useEffect, useRef } from "react"
import Link from "next/link"
import PsychologyCoachEntryLink from "./PsychologyCoachEntryLink"
import PsychologySummarySection from "./PsychologySummarySection"
import type { PsychologyAnalyticsReport } from "@/lib/psychology/reports/types"
import type { PsychologyCoachSummary } from "@/lib/psychology/reports/coach"
import { reliabilityLabel } from "@/lib/psychology/reports/metrics"
import {
  formatPsychologyMoney,
  formatPsychologyWinRate,
} from "@/lib/psychology/reports/format"

type PsychologyAnalyticsDetailProps = {
  report: PsychologyAnalyticsReport
  summary: PsychologyCoachSummary | null
  highlightedSectionID?: string | null
}

export default function PsychologyAnalyticsDetail({
  report,
  summary,
  highlightedSectionID,
}: PsychologyAnalyticsDetailProps) {
  const highlightRef = useRef<string | null>(null)

  useEffect(() => {
    if (!highlightedSectionID || highlightRef.current === highlightedSectionID) {
      return
    }
    highlightRef.current = highlightedSectionID
    const node = document.getElementById(`psych-section-${highlightedSectionID}`)
    node?.scrollIntoView({ behavior: "smooth", block: "start" })
  }, [highlightedSectionID])

  return (
    <div className="tt-psych-analytics space-y-6" data-testid="psychologyAnalytics.detail">
      <PsychologyCoachEntryLink />

      {summary ? <PsychologySummarySection summary={summary} showCoachLink={false} /> : null}

      <Link
        href="/check-in-history"
        className="flex w-full items-center justify-center rounded-lg border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-medium text-white hover:bg-white/10"
      >
        Check-In History
      </Link>

      {report.dashboardCards.length > 0 ? (
        <section className="space-y-3">
          <h2 className="text-base font-semibold text-white">Your Patterns</h2>
          <div className="space-y-2">
            {report.dashboardCards.map((card) => (
              <article
                key={card.id}
                className="rounded-xl border border-white/10 bg-white/5 p-4"
              >
                <p className="text-[10px] font-semibold uppercase tracking-wide text-blue-400">
                  {card.sectionTitle}
                </p>
                <p className="mt-1 text-sm font-semibold text-white">{card.headline}</p>
                <p className="mt-1 text-xs text-gray-400">{card.detail}</p>
                <p className="mt-2 text-[11px] text-gray-500">
                  {card.sampleSize} trades · {reliabilityLabel(card.reliability)}
                </p>
              </article>
            ))}
          </div>
        </section>
      ) : null}

      {report.sections.map((section) => (
        <section
          key={section.id}
          id={`psych-section-${section.id}`}
          className="scroll-mt-24 space-y-3"
        >
          <div>
            <h2 className="text-base font-semibold text-white">{section.title}</h2>
            {section.subtitle ? (
              <p className="text-xs text-gray-500">{section.subtitle}</p>
            ) : null}
          </div>

          {section.groups.length === 0 && section.footnote ? (
            <p className="text-sm text-gray-400">{section.footnote}</p>
          ) : (
            <div className="space-y-2">
              {section.groups.map((row) => (
                <article
                  key={row.id}
                  className={`rounded-xl border border-white/10 p-4 ${
                    row.highlight ? "bg-blue-500/10" : "bg-white/5"
                  }`}
                >
                  <p className="text-sm font-semibold text-white">{row.label}</p>
                  {row.metrics.reliability === "insufficient" ? (
                    <p className="mt-1 text-xs text-gray-400">
                      Not enough data yet ({row.metrics.tradeCount} trades)
                    </p>
                  ) : (
                    <>
                      <div className="mt-2 flex flex-wrap gap-4 text-xs">
                        <MetricPill label="Trades" value={String(row.metrics.tradeCount)} />
                        <MetricPill
                          label="Win"
                          value={formatPsychologyWinRate(row.metrics.winRate)}
                        />
                        <MetricPill
                          label="Avg"
                          value={formatPsychologyMoney(row.metrics.averagePnL ?? 0)}
                        />
                        <MetricPill
                          label="Exp"
                          value={formatPsychologyMoney(row.metrics.expectancy ?? 0)}
                        />
                      </div>
                      <p className="mt-2 text-[11px] text-gray-500">
                        {reliabilityLabel(row.metrics.reliability)}
                      </p>
                    </>
                  )}
                </article>
              ))}
            </div>
          )}

          {section.footnote && section.groups.length > 0 ? (
            <p className="text-xs text-gray-500">{section.footnote}</p>
          ) : null}
        </section>
      ))}
    </div>
  )
}

function MetricPill({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-[10px] uppercase text-gray-500">{label}</p>
      <p className="font-semibold tabular-nums text-white">{value}</p>
    </div>
  )
}
