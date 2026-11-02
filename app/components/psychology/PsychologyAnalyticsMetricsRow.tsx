"use client"

import {
  formatPsychologyMoney,
  formatPsychologyWinRate,
} from "@/lib/psychology/reports/format"
import { reliabilityLabel } from "@/lib/psychology/reports/metrics"
import type { PsychologyGroupMetrics } from "@/lib/psychology/reports/types"
import { countNoun } from "@/lib/countNoun"

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
  const isPreview = metrics.reliability === "insufficient" && metrics.tradeCount > 0

  return (
    <article
      className={`rounded-xl border border-white/10 p-4 max-md:p-3 ${
        highlight ? "bg-blue-500/10" : "bg-white/5"
      }`}
    >
      <p className="text-sm font-semibold text-white">{label}</p>
      {metrics.tradeCount === 0 ? (
        <p className="mt-1 text-xs text-gray-400">No trades in this group yet</p>
      ) : isPreview ? (
        <>
          <p className="mt-1 text-xs font-medium text-amber-200/90">
            Preview · {countNoun(metrics.tradeCount, "trade")}
          </p>
          <div className="mt-2 flex flex-wrap gap-4 text-xs max-md:grid max-md:grid-cols-2 max-md:gap-2">
            <MetricPill label="Win rate" value={formatPsychologyWinRate(metrics.winRate)} />
            <MetricPill
              label="Avg P&L / trade"
              value={formatPsychologyMoney(metrics.averagePnL ?? 0)}
            />
          </div>
          <p className="mt-2 text-[11px] text-gray-500">
            {reliabilityLabel(metrics.reliability)} — need 5+ trades for a reliable read
          </p>
        </>
      ) : (
        <>
          <div className="mt-2 flex flex-wrap gap-4 text-xs max-md:grid max-md:grid-cols-2 max-md:gap-2">
            <MetricPill label="Trades" value={String(metrics.tradeCount)} />
            <MetricPill label="Win rate" value={formatPsychologyWinRate(metrics.winRate)} />
            <MetricPill
              label="Avg P&L / trade"
              value={formatPsychologyMoney(metrics.averagePnL ?? 0)}
            />
            <MetricPill
              label="Expected $ / trade"
              value={formatPsychologyMoney(metrics.expectancy ?? 0)}
            />
          </div>
          <p className="mt-2 text-[11px] text-gray-500">
            {reliabilityLabel(metrics.reliability)}
          </p>
        </>
      )}
    </article>
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
