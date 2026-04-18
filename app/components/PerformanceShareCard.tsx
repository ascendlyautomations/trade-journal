"use client"

import { forwardRef, useMemo } from "react"
import {
  Area,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
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
  /** Loaded by parent — affiliate referral code */
  profile?: { referral_code?: string | null } | null
  stats: PerformanceStats
  /** ISO strings or Dates for bottom range line */
  rangeStart?: Date | string | number | null
  rangeEnd?: Date | string | number | null
  /** Used when range cannot be formatted */
  dateRangeFallback?: string
}

type ChartRow = { index: number; equity: number }

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

function formatRange(
  start: Date | string | number,
  end: Date | string | number
): string {
  const options: Intl.DateTimeFormatOptions = {
    month: "short",
    day: "numeric",
    year: "numeric",
  }
  const s = new Date(start)
  const e = new Date(end)
  if (Number.isNaN(s.getTime()) || Number.isNaN(e.getTime())) return ""
  return `${s.toLocaleDateString("en-US", options)} – ${e.toLocaleDateString("en-US", options)}`
}

const PerformanceShareCard = forwardRef<HTMLDivElement, PerformanceShareCardProps>(
  function PerformanceShareCard(
    {
      exportId,
      equityCurve,
      timeframeTitle,
      profile,
      stats,
      rangeStart,
      rangeEnd,
      dateRangeFallback,
    },
    ref
  ) {
    const pnl = Number(stats.totalPnL)
    const hasPnl = Number.isFinite(pnl)
    const positive = hasPnl && pnl >= 0

    const gradientId = `equity-${String(exportId ?? "share").replace(/[^a-zA-Z0-9_-]/g, "") || "share"}`

    const chartData = useMemo((): ChartRow[] => {
      const raw =
        equityCurve?.length >= 2
          ? equityCurve
          : [
              { step: 0, equity: 0 },
              { step: 1, equity: 0 },
            ]
      return raw.map((p) => ({
        index: typeof p.step === "number" ? p.step : Number(p.step) || 0,
        equity: Number(p.equity) || 0,
      }))
    }, [equityCurve])

    const winRateStr = stats.totalTrades
      ? `${stats.winRate.toFixed(1)}%`
      : "—"
    const tradesStr =
      stats.totalTrades > 0
        ? stats.totalTrades.toLocaleString()
        : "—"

    const codeTrim =
      profile?.referral_code != null &&
      String(profile.referral_code).trim() !== ""
        ? String(profile.referral_code).trim()
        : null

    let rangeDisplay = ""
    if (
      rangeStart != null &&
      rangeEnd != null &&
      rangeStart !== "" &&
      rangeEnd !== ""
    ) {
      rangeDisplay = formatRange(rangeStart, rangeEnd)
    }
    if (!rangeDisplay && dateRangeFallback) {
      rangeDisplay = dateRangeFallback
    }

    return (
      <div className="mx-auto box-border w-full max-w-[520px] px-5">
        <div
          ref={ref}
          id={exportId}
          className="w-full overflow-hidden rounded-3xl bg-gradient-to-br from-[#0b1a2a] via-[#123c4a] to-[#1c7f6e] shadow-2xl"
          style={{
            fontFamily:
              'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
          }}
        >
          <div className="w-full px-2 pt-4">
            <div className="flex h-[260px] w-full flex-col rounded-2xl bg-[#0b1a2a]/60 p-2 backdrop-blur-sm">
              <div className="min-h-0 flex-1">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart
                    data={chartData}
                    margin={{ top: 10, right: 6, left: 0, bottom: 18 }}
                  >
                    <defs>
                      <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#10b981" stopOpacity={0.35} />
                        <stop offset="100%" stopColor="#10b981" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid
                      stroke="rgba(255,255,255,0.04)"
                      vertical={false}
                    />
                    <XAxis
                      dataKey="index"
                      type="number"
                      tickFormatter={(value) => String(Math.floor(Number(value)))}
                      tick={{ fill: "#94a3b8", fontSize: 10 }}
                      axisLine={false}
                      tickLine={false}
                    />
                    <YAxis
                      tickFormatter={(value) =>
                        `$${Math.round(Number(value)).toLocaleString()}`
                      }
                      tick={{ fill: "#94a3b8", fontSize: 10 }}
                      axisLine={false}
                      tickLine={false}
                      width={48}
                    />
                    <Tooltip cursor={false} />
                    <Area
                      type="monotone"
                      dataKey="equity"
                      stroke="none"
                      fill={`url(#${gradientId})`}
                      isAnimationActive={false}
                    />
                    <Line
                      type="monotone"
                      dataKey="equity"
                      stroke="#10b981"
                      strokeWidth={3}
                      dot={false}
                      activeDot={{ r: 4 }}
                      isAnimationActive={false}
                    />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            </div>
          </div>

          <div className="flex flex-col px-7 py-6">
            <div className="mt-3 flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="text-xs tracking-widest text-gray-400">TRADE</p>
                <h2 className="text-3xl font-bold leading-tight text-white">
                  {timeframeTitle}
                </h2>
              </div>
              {codeTrim ? (
                <div className="shrink-0 rounded-full border border-emerald-400/20 bg-emerald-500/20 px-3 py-1 text-xs text-emerald-400">
                  CODE: {codeTrim}
                </div>
              ) : null}
            </div>

            <div className="mt-4">
              <p className="text-xs text-gray-400">P&amp;L</p>
              <h1
                className={`mt-1 text-4xl font-extrabold tabular-nums tracking-tight leading-tight md:text-5xl ${
                  !hasPnl
                    ? "text-gray-400"
                    : positive
                      ? "text-emerald-400"
                      : "text-red-400/90"
                }`}
              >
                {formatMoney(stats.totalPnL)}
              </h1>
            </div>

            <div className="mt-4 grid grid-cols-2 gap-5">
              <div className="rounded-xl border border-white/10 bg-white/5 p-5">
                <p className="text-xs tracking-wide text-gray-400">WIN RATE</p>
                <p className="mt-1 text-lg font-semibold tabular-nums text-white">
                  {winRateStr}
                </p>
              </div>
              <div className="rounded-xl border border-white/10 bg-white/5 p-5">
                <p className="text-xs tracking-wide text-gray-400">TRADES</p>
                <p className="mt-1 text-lg font-semibold tabular-nums text-white">
                  {tradesStr}
                </p>
              </div>
              <div className="col-span-2 rounded-xl border border-white/10 bg-white/5 p-5">
                <p className="text-xs tracking-wide text-gray-400">AVG RR</p>
                <p className="mt-1 text-lg font-semibold tabular-nums text-white">
                  {formatNumber(stats.avgRR)}
                </p>
              </div>
            </div>

            {rangeDisplay ? (
              <div className="mt-4 text-center text-sm text-gray-400">
                {rangeDisplay}
              </div>
            ) : null}
          </div>
        </div>
      </div>
    )
  }
)

PerformanceShareCard.displayName = "PerformanceShareCard"

export default PerformanceShareCard
