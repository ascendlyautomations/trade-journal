"use client"

import { dashboardInsightCardClass } from "@/app/components/dashboard/dashboardInsightStyles"
import {
  isPeriodicPsychologyTemplate,
  psychologyReportSubtitle,
} from "@/lib/psychology/reports/catalog"
import { psychologyPeriodBounds, reportIDForRef } from "@/lib/psychology/reports/periods"
import type {
  PsychologyReport,
  PsychologyReportPeriodRef,
} from "@/lib/psychology/reports/types"
import type { PsychologyReportCard } from "@/lib/usePsychologyReports"

function MetricCell({ label, value }: { label: string; value: string }) {
  return (
    <div className="tt-dash-psych-metric min-w-0 rounded-lg border border-white/10 bg-white/5 p-3">
      <p className="text-[11px] font-medium uppercase tracking-wide text-gray-400">
        {label}
      </p>
      <p className="mt-1 text-sm font-semibold tabular-nums text-white md:text-base">
        {value}
      </p>
    </div>
  )
}

export function PsychologyReportsCatalog({
  cards,
  onOpen,
}: {
  cards: PsychologyReportCard[]
  onOpen: (ref: PsychologyReportPeriodRef) => void
}) {
  return (
    <div className="space-y-2" data-testid="psychologyReports.catalog">
      {cards.map((card) => (
        <button
          key={card.template}
          type="button"
          onClick={() => onOpen(card.periodRef)}
          className="flex w-full items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/5 px-3 py-3 text-left transition hover:bg-white/10"
        >
          <span className="min-w-0">
            <span className="block truncate text-sm font-semibold text-white">
              {card.title}
            </span>
            <span className="block truncate text-xs text-gray-400">
              {card.subtitle || psychologyReportSubtitle(card.template)}
            </span>
          </span>
          <span className="shrink-0 text-xs text-gray-400">
            {isPeriodicPsychologyTemplate(card.template) &&
            card.availablePeriods.length > 1
              ? "Choose period →"
              : "Open →"}
          </span>
        </button>
      ))}
    </div>
  )
}

export function PsychologyReportDetail({
  report,
  periods,
  onPeriodChange,
}: {
  report: PsychologyReport
  periods: PsychologyReportPeriodRef[]
  onPeriodChange: (ref: PsychologyReportPeriodRef) => void
}) {
  const showPeriodPicker =
    isPeriodicPsychologyTemplate(report.periodRef.template) && periods.length > 1

  return (
    <div className="space-y-6" data-testid="psychologyReport.detail">
      <header className="space-y-2">
        <p className="text-xs font-medium uppercase tracking-wider text-blue-300">
          Psychology Report
        </p>
        <h2 className="text-xl font-semibold text-white md:text-2xl">
          {report.title}
        </h2>
        <p className="text-sm text-gray-400">{report.dateRangeLabel}</p>
        <p className="text-xs text-gray-500">
          Deterministic insights from your journal
        </p>
        {showPeriodPicker ? (
          <div className="flex flex-wrap gap-2 pt-2">
            {periods.map((ref) => {
              const bounds = psychologyPeriodBounds(ref)
              const selected = reportIDForRef(ref) === report.reportID
              return (
                <button
                  key={reportIDForRef(ref)}
                  type="button"
                  onClick={() => onPeriodChange(ref)}
                  className={`rounded-lg border px-3 py-1.5 text-xs font-medium transition md:text-sm ${
                    selected
                      ? "border-blue-400/60 bg-blue-500/20 text-white"
                      : "border-white/10 bg-white/5 text-gray-200 hover:bg-white/10"
                  }`}
                >
                  {bounds.dateRangeLabel}
                </button>
              )
            })}
          </div>
        ) : null}
      </header>

      {report.doingWell.length > 0 ? (
        <section className="space-y-2">
          <h3 className="text-sm font-semibold text-emerald-300">What Went Well</h3>
          <ul className="space-y-2 text-sm text-gray-300">
            {report.doingWell.map((item) => (
              <li
                key={item}
                className="rounded-lg border border-emerald-500/20 bg-emerald-500/5 px-3 py-2"
              >
                {item}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {report.sections.map((section) => (
        <section
          key={section.id}
          className={`${dashboardInsightCardClass} space-y-3`}
        >
          <div>
            <h3 className="text-sm font-semibold text-white">{section.title}</h3>
            {section.subtitle ? (
              <p className="mt-0.5 text-xs text-gray-400">{section.subtitle}</p>
            ) : null}
          </div>
          {section.metrics.length > 0 ? (
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {section.metrics.map((row) => (
                <MetricCell key={`${row.label}:${row.value}`} label={row.label} value={row.value} />
              ))}
            </div>
          ) : null}
          {section.bullets.length > 0 ? (
            <ul className="space-y-1.5 text-sm text-gray-300">
              {section.bullets.map((bullet) => (
                <li key={bullet}>• {bullet}</li>
              ))}
            </ul>
          ) : null}
        </section>
      ))}

      {report.watchItems.length > 0 ? (
        <section className="space-y-2">
          <h3 className="text-sm font-semibold text-amber-300">What to Watch</h3>
          <ul className="space-y-2 text-sm text-gray-300">
            {report.watchItems.map((item) => (
              <li
                key={item}
                className="rounded-lg border border-amber-500/20 bg-amber-500/5 px-3 py-2"
              >
                {item}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {report.comparisons.length > 0 ? (
        <section className={`${dashboardInsightCardClass} space-y-3`}>
          <h3 className="text-sm font-semibold text-white">Period Comparisons</h3>
          {report.comparisons.map((comparison) => (
            <div key={comparison.headline}>
              <p className="text-sm font-semibold text-white">{comparison.headline}</p>
              <p className="text-sm text-gray-400">{comparison.detail}</p>
            </div>
          ))}
        </section>
      ) : null}
    </div>
  )
}
