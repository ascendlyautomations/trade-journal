"use client"

import { formatRR } from "@/lib/formatDisplay"
import type { DashboardRrTargetAnalysis } from "@/lib/dashboardRrTargetAnalysis"
import { normalizeAIGeneratedText } from "@/lib/normalizeAIGeneratedText"
import { mwDashText } from "./mobileWebDashboardChrome"

const prose = (text: string) => normalizeAIGeneratedText(text)

function formatTargetAttainmentPct(ratio: number | null): string {
  if (ratio == null) return "—"
  return `${Math.round(ratio * 100)}%`
}

export default function MobileWebDashboardRrTarget({
  analysis,
}: {
  analysis: DashboardRrTargetAnalysis
}) {
  if (analysis.pairedCount === 0) {
    const [first, ...rest] = analysis.bullets
    return (
      <div className="flex flex-col gap-1.5">
        <p className={`text-[13px] font-semibold leading-snug ${mwDashText.primary}`}>
          {prose(analysis.headline ?? "Not enough paired R:R yet")}
        </p>
        <p className={`text-[12px] leading-snug ${mwDashText.muted}`}>
          {prose(
            first ??
              "Only trades with both Targeted Risk/Reward and Max R:R Reached appear here."
          )}
        </p>
        {rest.map((line) => (
          <p key={line} className={`text-[11px] leading-snug ${mwDashText.tertiary}`}>
            {prose(line)}
          </p>
        ))}
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-3">
      {analysis.sampleSummary ? (
        <p className={`text-[11px] leading-snug ${mwDashText.tertiary}`}>
          {prose(analysis.sampleSummary)}
        </p>
      ) : null}

      <div className="grid grid-cols-2 gap-3">
        <div>
          <p className={`text-[11px] ${mwDashText.tertiary}`}>Avg target R:R</p>
          <p className={`mt-0.5 text-[15px] font-semibold tabular-nums ${mwDashText.primary}`}>
            {formatRR(analysis.avgTargetRr)}
          </p>
        </div>
        <div>
          <p className={`text-[11px] ${mwDashText.tertiary}`}>Avg max reached</p>
          <p className={`mt-0.5 text-[15px] font-semibold tabular-nums ${mwDashText.primary}`}>
            {formatRR(analysis.avgMaxRrReached)}
          </p>
        </div>
      </div>

      {analysis.avgTargetAttainmentRatio != null ? (
        <div>
          <p className={`text-[11px] ${mwDashText.tertiary}`}>Target attainment %</p>
          <p className={`mt-0.5 text-[15px] font-semibold tabular-nums ${mwDashText.accent}`}>
            {formatTargetAttainmentPct(analysis.avgTargetAttainmentRatio)}
          </p>
          <p className={`mt-1 text-[11px] leading-snug ${mwDashText.tertiary}`}>
            Max R:R reached ÷ targeted R:R on paired trades only. Can exceed 100%
            when price runs past target.
          </p>
        </div>
      ) : null}

      {analysis.headline ? (
        <p className={`text-[13px] font-medium leading-snug ${mwDashText.primary}`}>
          {prose(analysis.headline)}
        </p>
      ) : null}

      {analysis.bullets.length > 0 ? (
        <ul className="space-y-1.5">
          {analysis.bullets.map((line) => (
            <li key={line} className="flex gap-2">
              <span className="mt-[7px] h-1 w-1 shrink-0 rounded-full bg-[color:var(--tt-accent,#4ec4e0)]" />
              <span className={`text-[13px] leading-snug ${mwDashText.muted}`}>
                {prose(line)}
              </span>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  )
}
