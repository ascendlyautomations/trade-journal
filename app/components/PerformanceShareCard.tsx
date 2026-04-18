"use client"

import { forwardRef, useMemo } from "react"
import {
  Line,
  LineChart,
  ResponsiveContainer,
} from "recharts"
import type { EquityCurvePoint, PerformanceStats } from "@/lib/performanceShare"

/**
 * Duplicate of `TradeShareCard` layout/styling; trade fields swapped for performance data.
 */
export type PerformanceShareCardProps = {
  /** For html-to-image: target this id with `document.getElementById` */
  exportId?: string
  equityCurve: EquityCurvePoint[]
  /** Large title (same position/size as ticker) — e.g. WEEKLY */
  timeframeTitle: string
  /** Badge text (same position as Long/Short) — e.g. WEEKLY */
  timeframeBadge: string
  stats: PerformanceStats
  /** Same position as trade date line */
  dateRangeLabel: string
}

function formatMoney(value: unknown): string {
  if (value === null || value === undefined) return "—"
  const number = Number(value)
  if (Number.isNaN(number)) return "—"
  return number < 0
    ? `-$${Math.abs(number).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
    : `$${number.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
}

function formatNumber(value: unknown): string {
  if (value === null || value === undefined) return "—"
  const number = Number(value)
  if (Number.isNaN(number)) return "—"
  return number.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

const LINE_STROKE = "#34d399"

const PerformanceShareCard = forwardRef<HTMLDivElement, PerformanceShareCardProps>(
  function PerformanceShareCard(
    {
      exportId,
      equityCurve,
      timeframeTitle,
      timeframeBadge,
      stats,
      dateRangeLabel,
    },
    ref
  ) {
    const pnl = Number(stats.totalPnL)
    const hasPnl = Number.isFinite(pnl)
    const positive = hasPnl && pnl >= 0

    const chartData = useMemo(() => {
      if (equityCurve && equityCurve.length >= 2) return equityCurve
      return [
        { step: 0, equity: 0 },
        { step: 1, equity: 0 },
      ]
    }, [equityCurve])

    const winRateStr = stats.totalTrades
      ? `${stats.winRate.toFixed(1)}%`
      : "—"
    const tradesStr =
      stats.totalTrades > 0
        ? stats.totalTrades.toLocaleString()
        : "—"

    return (
      <div
        ref={ref}
        id={exportId}
        className="box-border w-[420px] overflow-hidden rounded-3xl border border-white/[0.12] shadow-2xl"
        style={{
          backgroundColor: "#0a0f1c",
          fontFamily:
            'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
        }}
      >
        <div className="relative aspect-[4/3] w-full bg-black/50">
          <div className="absolute inset-0">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart
                data={chartData}
                margin={{ top: 8, right: 8, left: 8, bottom: 8 }}
              >
                <Line
                  type="monotone"
                  dataKey="equity"
                  stroke={LINE_STROKE}
                  strokeWidth={3}
                  dot={false}
                  isAnimationActive={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="space-y-5 px-7 pb-8 pt-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-[11px] font-semibold uppercase tracking-[0.2em] text-slate-500">
                Trade
              </p>
              <p className="mt-1 text-3xl font-bold tracking-tight text-white">
                {timeframeTitle}
              </p>
            </div>
            <span className="mt-7 shrink-0 rounded-full border border-emerald-400/40 bg-emerald-500/15 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-emerald-300">
              {timeframeBadge}
            </span>
          </div>

          <div>
            <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-500">
              P&amp;L
            </p>
            <p
              className={`mt-1 text-[2.65rem] font-bold leading-none tabular-nums tracking-tight ${
                !hasPnl
                  ? "text-slate-400"
                  : positive
                    ? "text-emerald-400"
                    : "text-red-400"
              }`}
            >
              {formatMoney(stats.totalPnL)}
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3 text-sm">
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.04] px-4 py-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
                Win Rate
              </p>
              <p className="mt-1 font-semibold tabular-nums text-white">
                {winRateStr}
              </p>
            </div>
            <div className="rounded-2xl border border-white/[0.08] bg-white/[0.04] px-4 py-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
                Trades
              </p>
              <p className="mt-1 font-semibold tabular-nums text-white">
                {tradesStr}
              </p>
            </div>
          </div>

          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.04] px-4 py-3 text-sm">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">
              Avg RR
            </p>
            <p className="mt-1 font-medium text-gray-100">
              {formatNumber(stats.avgRR)}
            </p>
          </div>

          {dateRangeLabel ? (
            <p className="text-center text-xs text-slate-600">{dateRangeLabel}</p>
          ) : null}
        </div>
      </div>
    )
  }
)

PerformanceShareCard.displayName = "PerformanceShareCard"

export default PerformanceShareCard
