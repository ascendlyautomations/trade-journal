"use client"

import {
  formatOptionalPsychologyMoney,
  formatPsychologyWinRate,
} from "@/lib/psychology/reports/format"
import type { PsychologyGroupMetrics } from "@/lib/psychology/reports/types"

type PsychologyAnalyticsMetricsRowProps = {
  label: string
  metrics: PsychologyGroupMetrics
  highlight?: boolean
}

export default function PsychologyAnalyticsMetricsRow({
  label,
  metrics,
  highlight = false,
}: PsychologyAnalyticsMetricsRowProps) {
  if (metrics.tradeCount < 5) return null
  const average = formatOptionalPsychologyMoney(metrics.averagePnL)
  const winRate = metrics.winRate == null ? null : formatPsychologyWinRate(metrics.winRate)

  return (
    <article
      className={`flex flex-wrap items-baseline justify-between gap-2 rounded-xl border border-white/10 px-4 py-3 max-md:px-3 ${
        highlight ? "bg-blue-500/10" : "bg-white/5"
      }`}
    >
      <p className="text-sm font-semibold text-white">{label}</p>
      <p className="text-sm tabular-nums text-gray-200">
        {winRate ? <span>{winRate} win rate</span> : null}
        {winRate && average ? <span className="text-gray-500"> · </span> : null}
        {average ? <span>{average} avg</span> : null}
      </p>
    </article>
  )
}
