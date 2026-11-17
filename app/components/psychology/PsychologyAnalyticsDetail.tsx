"use client"

import { useEffect, useRef, useState } from "react"
import Link from "next/link"
import PsychologyCoachEntryLink from "./PsychologyCoachEntryLink"
import PsychologySummarySection from "./PsychologySummarySection"
import PsychologyAnalyticsOverview from "./PsychologyAnalyticsOverview"
import PsychologyAnalyticsMetricsRow from "./PsychologyAnalyticsMetricsRow"
import type { PsychologyAnalyticsReport } from "@/lib/psychology/reports/types"
import type { PsychologyCoachSummary } from "@/lib/psychology/reports/coach"
import type { TraderDailyCheckIn } from "@/lib/dailyCheckIn/types"
import type { PsychologyReportTrade } from "@/lib/psychology/reports/types"

type PsychologyAnalyticsDetailProps = {
  report: PsychologyAnalyticsReport
  summary: PsychologyCoachSummary | null
  highlightedSectionID?: string | null
  journalTrades?: readonly PsychologyReportTrade[]
  checkIns?: readonly TraderDailyCheckIn[]
  scopeLabel?: string | null
}

export default function PsychologyAnalyticsDetail({
  report,
  summary,
  highlightedSectionID,
  journalTrades = [],
  checkIns = [],
  scopeLabel,
}: PsychologyAnalyticsDetailProps) {
  const highlightRef = useRef<string | null>(null)
  const [advancedOpen, setAdvancedOpen] = useState(false)
  const insightCards = report.dashboardCards
  const advancedSections = report.sections

  useEffect(() => {
    if (!highlightedSectionID || highlightRef.current === highlightedSectionID) {
      return
    }
    highlightRef.current = highlightedSectionID
    if (advancedSections.some((section) => section.id === highlightedSectionID)) {
      setAdvancedOpen(true)
    }
    const node = document.getElementById(`psych-section-${highlightedSectionID}`)
    node?.scrollIntoView({ behavior: "smooth", block: "start" })
  }, [advancedSections, highlightedSectionID])

  return (
    <div
      className="tt-psych-analytics space-y-6 max-md:flex max-md:flex-col max-md:gap-4 max-md:space-y-0"
      data-testid="psychologyAnalytics.detail"
    >
      <div className="max-md:order-3">
        <PsychologyCoachEntryLink />
      </div>

      <div className="max-md:order-1">
        <PsychologyAnalyticsOverview
          report={report}
          journalTrades={journalTrades}
          checkIns={checkIns}
          scopeLabel={scopeLabel}
        />
      </div>

      <Link
        href="/check-in-history"
        className="flex w-full items-center justify-center rounded-lg border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-medium text-white hover:bg-white/10 max-md:order-4 max-md:min-h-11"
      >
        Check-In History
      </Link>

      <div className="max-md:order-5">
      {insightCards.length > 0 ? (
        <section className="space-y-3">
          <h2 className="text-base font-semibold text-white">Insights</h2>
          <p className="text-xs text-gray-500">
            What your results have lined up with. These are associations, not causes.
          </p>
          <div className="space-y-2">
            {insightCards.map((card) => (
              <article
                key={card.id}
                className="rounded-xl border border-white/10 bg-white/5 p-4 max-md:p-3"
              >
                <p className="text-[10px] font-semibold uppercase tracking-wide text-blue-400">
                  {card.sectionTitle}
                </p>
                <p className="mt-1 text-sm font-semibold text-white">{card.headline}</p>
                <p className="mt-1 text-xs text-gray-400">{card.detail}</p>
              </article>
            ))}
          </div>
        </section>
      ) : (
        <div className="rounded-xl border border-white/10 bg-white/5 p-4 max-md:p-3">
          <p className="text-sm font-medium text-white">No insight yet</p>
          <p className="mt-1 text-xs text-gray-400">
            A comparison appears after each side has at least 8 trades and a real
            difference in results.
          </p>
        </div>
      )}
      </div>

      {summary ? (
        <div className="max-md:order-6">
          <PsychologySummarySection
            summary={summary}
            showCoachLink={false}
            recommendationsOnly
          />
        </div>
      ) : null}

      {advancedSections.length > 0 ? (
      <section className="space-y-3 max-md:order-7">
        <button
          type="button"
          className="flex w-full items-center justify-between rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-left max-md:min-h-11 max-md:px-3"
          onClick={() => setAdvancedOpen((open) => !open)}
          aria-expanded={advancedOpen}
          data-testid="psychologyAnalytics.advancedToggle"
        >
          <span>
            <span className="block text-sm font-semibold text-white">Advanced analytics</span>
            <span className="block text-xs text-gray-500">
              Both sides of each comparison
            </span>
          </span>
          <span className="text-sm text-blue-400">{advancedOpen ? "Hide" : "Show"}</span>
        </button>

        {advancedOpen
          ? advancedSections.map((section) => (
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
                      <PsychologyAnalyticsMetricsRow
                        key={row.id}
                        label={row.label}
                        metrics={row.metrics}
                        highlight={row.highlight}
                      />
                    ))}
                  </div>
                )}

                {section.footnote && section.groups.length > 0 ? (
                  <p className="text-xs text-gray-500">{section.footnote}</p>
                ) : null}
              </section>
            ))
          : null}
      </section>
      ) : null}
    </div>
  )
}
