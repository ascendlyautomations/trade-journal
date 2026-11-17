"use client"

import Link from "next/link"
import type { PsychologyCoachSummary } from "@/lib/psychology/reports/coach"

type PsychologySummarySectionProps = {
  summary: PsychologyCoachSummary
  coachHref?: string
  showCoachLink?: boolean
  /** Analytics page shows actions only. Written reports keep the fuller summary. */
  recommendationsOnly?: boolean
}

export default function PsychologySummarySection({
  summary,
  coachHref = "/psychology/coach",
  showCoachLink = true,
  recommendationsOnly = false,
}: PsychologySummarySectionProps) {
  if (recommendationsOnly && summary.recommendations.length === 0) return null

  return (
    <section
      className="rounded-xl border border-white/10 bg-white/5 p-4 max-md:p-3"
      data-testid="psychologyCoach.summary"
    >
      <h2 className="text-lg font-bold text-white">
        {recommendationsOnly ? "Recommendations" : summary.title}
      </h2>
      {!recommendationsOnly && summary.overview ? (
        <p className="mt-2 text-sm text-gray-300">{summary.overview}</p>
      ) : null}

      {!recommendationsOnly && summary.doingWell.length > 0 ? (
        <Bullets title="What You're Doing Well" items={summary.doingWell} tone="text-emerald-400" />
      ) : null}
      {!recommendationsOnly && summary.watchItems.length > 0 ? (
        <Bullets title="What to Watch" items={summary.watchItems} tone="text-amber-400" />
      ) : null}
      {summary.recommendations.length > 0 ? (
        <Bullets
          title="Possible Guardrails"
          items={summary.recommendations}
          tone="text-blue-400"
        />
      ) : null}

      {showCoachLink ? (
        <Link
          href={coachHref}
          className="mt-4 flex w-full items-center justify-center rounded-lg bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-600"
        >
          Open Psychology Coach
        </Link>
      ) : null}
    </section>
  )
}

function Bullets({
  title,
  items,
  tone,
}: {
  title: string
  items: string[]
  tone: string
}) {
  return (
    <div className="mt-4">
      <h3 className="text-sm font-semibold text-white">{title}</h3>
      <ul className="mt-2 space-y-1.5">
        {items.map((item) => (
          <li key={item} className="flex gap-2 text-sm text-gray-400">
            <span className={`mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full ${tone} bg-current`} />
            <span>{item}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}
