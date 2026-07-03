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
import { SITE_NAME } from "@/lib/site"
import { PERFORMANCE_SHARE_EXPORT_WIDTH } from "@/lib/shareImageCaptureConstants"
import { formatHoldDurationSeconds } from "@/lib/tradeTimingDisplay"

export type PerformanceShareCardProps = {
  /** For html-to-image: target this id with `document.getElementById` */
  exportId?: string
  equityCurve: EquityCurvePoint[]
  /** Large title (same position/size as ticker) — e.g. WEEKLY */
  timeframeTitle: string
  profile?: {
    referral_code?: string | null
    username?: string | null
  } | null
  stats: PerformanceStats
  rangeStart?: Date | string | number | null
  rangeEnd?: Date | string | number | null
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
    minimumFractionDigits: 1,
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

const statBoxClass =
  "rounded-xl border border-cyan-300/10 bg-white/[0.06] px-3 py-3 text-center"

const statLabelClass =
  "text-[10px] font-semibold uppercase tracking-wide text-blue-100/55"

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
      stats.totalTrades > 0 ? stats.totalTrades.toLocaleString() : "—"
    const avgRrStr = formatNumber(stats.avgRR)
    const avgTimeStr =
      stats.avgDurationSeconds != null
        ? formatHoldDurationSeconds(stats.avgDurationSeconds) ?? "—"
        : "—"
    const mostTradedStr = stats.mostTradedTicker ?? "—"

    const codeTrim =
      profile?.referral_code != null &&
      String(profile.referral_code).trim() !== ""
        ? String(profile.referral_code).trim()
        : null

    const usernameTrim =
      profile?.username != null && String(profile.username).trim() !== ""
        ? String(profile.username).trim().replace(/^@+/, "")
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
      <div
        className="mx-auto box-border shrink-0"
        style={{ width: PERFORMANCE_SHARE_EXPORT_WIDTH }}
      >
        <div
          ref={ref}
          id={exportId}
          className="relative overflow-hidden rounded-[28px] border border-cyan-300/20 bg-gradient-to-br from-[#061427] via-[#0b2d55] to-[#0f7ea8] shadow-2xl"
          style={{
            width: PERFORMANCE_SHARE_EXPORT_WIDTH,
            minWidth: PERFORMANCE_SHARE_EXPORT_WIDTH,
            boxSizing: "border-box",
            fontFamily:
              'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
          }}
        >
          <div
            className="pointer-events-none absolute -right-20 -top-20 h-44 w-44 rounded-full bg-cyan-400/20"
            style={{
              background:
                "radial-gradient(circle, rgba(34,211,238,0.22) 0%, transparent 70%)",
            }}
          />
          <div
            className="pointer-events-none absolute -bottom-16 -left-20 h-48 w-48 rounded-full bg-blue-500/15"
            style={{
              background:
                "radial-gradient(circle, rgba(59,130,246,0.18) 0%, transparent 70%)",
            }}
          />

          <div className="relative p-4 pb-0">
            <div className="relative h-[220px] w-full overflow-hidden rounded-2xl border border-cyan-300/20 bg-[#07152a]/70 shadow-inner shadow-black/30">
              <div className="min-h-0 h-full p-2">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart
                    data={chartData}
                    margin={{ top: 8, right: 6, left: 0, bottom: 16 }}
                  >
                    <defs>
                      <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#6ee7b7" stopOpacity={0.35} />
                        <stop offset="100%" stopColor="#6ee7b7" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid
                      stroke="rgba(255,255,255,0.06)"
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
                      stroke="#6ee7b7"
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

          <div className="relative flex flex-col px-6 pb-5 pt-5">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-[10px] font-semibold uppercase tracking-[0.28em] text-cyan-200/70">
                  Performance Recap
                </p>
                <h2 className="mt-1 truncate text-4xl font-black leading-none tracking-tight text-white">
                  {timeframeTitle}
                </h2>
              </div>
              {codeTrim ? (
                <div className="shrink-0 rounded-full border border-cyan-300/20 bg-cyan-300/10 px-2.5 py-1 text-[10px] font-semibold text-cyan-100">
                  CODE {codeTrim}
                </div>
              ) : null}
            </div>

            <div className="mt-4 rounded-2xl border border-cyan-300/15 bg-[#031022]/45 px-4 py-4">
              <p className="text-[10px] font-semibold uppercase tracking-[0.24em] text-blue-100/60">
                Net P&amp;L
              </p>
              <h1
                className={`mt-1 text-[2.5rem] font-black leading-none tabular-nums tracking-tight ${
                  !hasPnl
                    ? "text-gray-300"
                    : positive
                      ? "text-emerald-300"
                      : "text-red-300"
                }`}
              >
                {formatMoney(stats.totalPnL)}
              </h1>
            </div>

            <div className="mt-4 grid grid-cols-2 gap-2">
              <div className={statBoxClass}>
                <p className={statLabelClass}>Win Rate</p>
                <p className="mt-1 text-base font-bold tabular-nums text-white">
                  {winRateStr}
                </p>
              </div>
              <div className={statBoxClass}>
                <p className={statLabelClass}>Trades</p>
                <p className="mt-1 text-base font-bold tabular-nums text-white">
                  {tradesStr}
                </p>
              </div>
            </div>

            <div className="mt-3 grid grid-cols-3 gap-2">
              {[
                ["Avg RR", avgRrStr],
                ["Avg Time", avgTimeStr],
                ["Most Traded", mostTradedStr],
              ].map(([label, value]) => (
                <div key={label} className={statBoxClass}>
                  <p className={statLabelClass}>{label}</p>
                  <p className="mt-1 truncate text-base font-bold tabular-nums text-white">
                    {value}
                  </p>
                </div>
              ))}
            </div>

            {rangeDisplay ? (
              <div className="mt-3 rounded-xl border border-cyan-300/10 bg-[#031022]/40 px-3 py-3 text-center">
                <p className={statLabelClass}>Date Range</p>
                <p className="mt-1 text-sm font-medium leading-snug text-cyan-50">
                  {rangeDisplay}
                </p>
              </div>
            ) : null}

            <div className="mt-5 flex items-center justify-between border-t border-cyan-300/15 pt-4">
              <div className="flex min-w-0 flex-1 items-center gap-2">
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-cyan-300/30 bg-cyan-300/15 text-xs font-black text-cyan-100">
                  TT
                </div>
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-black leading-none tracking-tight text-white">
                    {SITE_NAME}
                  </p>
                  <p className="mt-0.5 flex min-w-0 items-center justify-between gap-3 text-[9px] uppercase tracking-[0.22em] text-cyan-100/55">
                    <span className="shrink-0">Journal. Review. Improve.</span>
                    {usernameTrim ? (
                      <span className="truncate font-medium normal-case tracking-normal text-cyan-100/40">
                        - @{usernameTrim}
                      </span>
                    ) : null}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    )
  }
)

PerformanceShareCard.displayName = "PerformanceShareCard"

export default PerformanceShareCard
