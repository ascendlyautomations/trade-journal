"use client"

import { formatRR } from "@/lib/formatDisplay"
import type { DashboardRrTargetAnalysis } from "@/lib/dashboardRrTargetAnalysis"

function formatTargetAttainmentPct(ratio: number | null): string {
  if (ratio == null) return "—"
  return `${Math.round(ratio * 100)}%`
}

export default function DashboardRrTargetAnalysisPanel({
  analysis,
}: {
  analysis: DashboardRrTargetAnalysis
}) {
  if (analysis.pairedCount === 0) {
    return (
      <div className="space-y-2">
        {analysis.headline ? (
          <p className="text-sm font-medium text-gray-200">{analysis.headline}</p>
        ) : null}
        {analysis.bullets.length > 0 ? (
          <ul className="space-y-2 text-sm leading-snug text-gray-400">
            {analysis.bullets.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        ) : (
          <p className="text-sm leading-snug text-gray-400">
            Only trades with both Targeted Risk/Reward and Max R:R Reached appear
            here. This is separate from realized profit and from the dashboard
            Avg Max R:R KPI.
          </p>
        )}
      </div>
    )
  }

  return (
    <div className="space-y-3">
      {analysis.sampleSummary ? (
        <p className="text-xs font-medium leading-snug text-gray-400">
          {analysis.sampleSummary}
        </p>
      ) : null}

      <div className="grid grid-cols-2 gap-x-3 gap-y-2 text-sm">
        <div>
          <p className="text-[11px] uppercase tracking-wide text-gray-400">
            Avg target R:R
          </p>
          <p className="font-semibold tabular-nums text-white">
            {formatRR(analysis.avgTargetRr)}
          </p>
        </div>
        <div>
          <p className="text-[11px] uppercase tracking-wide text-gray-400">
            Avg max reached
          </p>
          <p className="font-semibold tabular-nums text-white">
            {formatRR(analysis.avgMaxRrReached)}
          </p>
        </div>
        {analysis.avgTargetAttainmentRatio != null ? (
          <div className="col-span-2">
            <p className="text-[11px] uppercase tracking-wide text-gray-400">
              Target attainment %
            </p>
            <p className="font-semibold tabular-nums text-blue-200">
              {formatTargetAttainmentPct(analysis.avgTargetAttainmentRatio)}
            </p>
            <p className="mt-0.5 text-[10px] leading-snug text-gray-500">
              Max R:R reached ÷ targeted R:R on paired trades only. Can exceed
              100% when price runs past target. Not realized P&amp;L capture.
            </p>
          </div>
        ) : null}
      </div>

      {analysis.headline ? (
        <p className="text-sm font-medium leading-snug text-gray-100">
          {analysis.headline}
        </p>
      ) : null}

      {analysis.bullets.length > 0 ? (
        <ul className="space-y-2 text-sm leading-snug text-gray-300">
          {analysis.bullets.map((line) => (
            <li key={line} className="flex gap-2">
              <span className="mt-1.5 h-1 w-1 shrink-0 rounded-full bg-blue-400" />
              <span>{line}</span>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  )
}
