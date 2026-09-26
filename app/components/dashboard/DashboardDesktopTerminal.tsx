"use client"

import type { ReactNode } from "react"
import DashboardEquityCurve, {
  type EquityChartPoint,
} from "@/app/components/dashboard/DashboardEquityCurve"
import type { WeekdayChartPoint } from "@/app/components/dashboard/DashboardWeekdayChart"
import type { SessionBuckets } from "@/app/components/dashboard/DashboardSessionChart"
import {
  DASHBOARD_SESSION_DISPLAY_ORDER,
  type DashboardSessionBucket,
} from "@/lib/dashboardSessionBuckets"
import type { HoldTimeStats } from "@/lib/dashboardHoldTimeStats"
import type { LongShortPerformance } from "@/lib/dashboardLongShortStats"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import { formatHoldDurationSeconds } from "@/lib/tradeTimingDisplay"

type ExpectancySummary = { expectancy: number } | null
type StreakSummary = {
  currentStreak: number
  currentType: "win" | "loss" | "even" | null
} | null
type TradingHoursSummary = {
  hourlyMap: Record<number, number>
  hasValidTradingHoursData: boolean
  bestHour: number | null
  worstHour: number | null
} | null

export type DashboardDesktopTerminalProps = {
  isPro: boolean
  deferredSectionsReady: boolean
  timeframeLabel: string
  propFirmDetails?: ReactNode
  totalTrades: number
  totalPnL: number
  winRate: number
  winCount: number
  lossCount: number
  profitFactor: number
  avgRR: number | null
  expectancyData: ExpectancySummary
  bestDay: number
  bestTrade: number
  avgWin: number
  avgLoss: number
  biggestLoss: number
  worstDay: number
  maxDrawdown: number
  showDrawdown: boolean
  bestWinStreak: number
  streakData: StreakSummary
  showEquity: boolean
  equityData: EquityChartPoint[]
  showSessions: boolean
  sessionBuckets: SessionBuckets
  weekdayData: WeekdayChartPoint[]
  hourData: TradingHoursSummary
  longShortPerformance: LongShortPerformance
  holdTimeStats: HoldTimeStats
}

function pnlClass(value: number) {
  if (value > 0) return "text-green-400"
  if (value < 0) return "text-red-400"
  return "text-white"
}

function barTone(value: number) {
  if (value > 0) return "tt-dash-bar-pos"
  if (value < 0) return "tt-dash-bar-neg"
  return "tt-dash-bar-flat"
}

function Panel({
  children,
  className = "",
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <section
      className={`rounded-xl border border-white/10 bg-white/10 p-4 ${className}`.trim()}
    >
      {children}
    </section>
  )
}

function SectionTitle({ children }: { children: ReactNode }) {
  return <h2 className="tt-dash-section-title mb-3">{children}</h2>
}

function MetricLine({
  label,
  value,
  valueClassName = "text-white",
}: {
  label: string
  value: ReactNode
  valueClassName?: string
}) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-white/10 py-2 last:border-b-0">
      <span className="tt-dash-label">{label}</span>
      <span className={`text-sm font-semibold tabular-nums ${valueClassName}`}>
        {value}
      </span>
    </div>
  )
}

function KpiCell({
  label,
  value,
  valueClassName = "tt-dash-value",
}: {
  label: string
  value: ReactNode
  valueClassName?: string
}) {
  return (
    <div className="tt-dash-strip-cell">
      <p className="tt-dash-label">{label}</p>
      <p className={valueClassName}>{value}</p>
    </div>
  )
}

function HBar({
  label,
  detail,
  amount,
  max,
  valueLabel,
  neutral = false,
}: {
  label: string
  detail?: string
  amount: number
  max: number
  valueLabel: string
  neutral?: boolean
}) {
  const width =
    amount === 0 || max <= 0 ? 0 : Math.max(6, (Math.abs(amount) / max) * 100)
  return (
    <div className="grid grid-cols-[5.5rem_minmax(0,1fr)_auto] items-center gap-3">
      <div className="min-w-0">
        <p className="truncate text-xs font-medium text-gray-200">{label}</p>
        {detail ? <p className="truncate text-[11px] text-gray-400">{detail}</p> : null}
      </div>
      <div className="h-2.5 overflow-hidden rounded-full bg-black/20">
        <div
          className={`h-full rounded-full ${neutral ? "tt-dash-bar-flat" : barTone(amount)}`}
          style={{ width: `${Math.min(100, width)}%` }}
        />
      </div>
      <span
        className={`text-sm font-semibold tabular-nums ${neutral ? "text-white" : pnlClass(amount)}`}
      >
        {valueLabel}
      </span>
    </div>
  )
}

function formatHour(hour: number, compact = false) {
  const suffix = hour >= 12 ? (compact ? "p" : "PM") : compact ? "a" : "AM"
  const hour12 = hour % 12 || 12
  return compact ? `${hour12}${suffix}` : `${hour12} ${suffix}`
}

function sessionLabel(name: DashboardSessionBucket) {
  return name === "NY" ? "New York" : name
}

function holdLabel(seconds: number | null) {
  if (seconds == null) return "—"
  return formatHoldDurationSeconds(Math.round(seconds)) ?? "—"
}

function WinLossRing({
  winRate,
  winCount,
  lossCount,
}: {
  winRate: number
  winCount: number
  lossCount: number
}) {
  const radius = 46
  const circumference = 2 * Math.PI * radius
  const clamped = Math.max(0, Math.min(100, winRate))
  const winArc = (clamped / 100) * circumference

  return (
    <div className="flex items-center gap-4">
      <div className="relative h-[120px] w-[120px] shrink-0">
        <svg viewBox="0 0 120 120" className="h-full w-full -rotate-90">
          <circle
            cx="60"
            cy="60"
            r={radius}
            fill="none"
            className="tt-dash-ring-track"
            stroke="currentColor"
            strokeWidth="10"
          />
          <circle
            cx="60"
            cy="60"
            r={radius}
            fill="none"
            className="tt-dash-ring-win"
            stroke="currentColor"
            strokeWidth="10"
            strokeLinecap="butt"
            strokeDasharray={`${winArc} ${circumference}`}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-xl font-semibold tabular-nums text-white">
            {winRate.toFixed(0)}%
          </span>
          <span className="text-[10px] uppercase tracking-wide text-gray-400">
            Win rate
          </span>
        </div>
      </div>
      <div className="min-w-0 flex-1 space-y-2">
        <p className="flex items-center justify-between text-sm">
          <span className="text-gray-300">Wins</span>
          <span className="font-semibold tabular-nums text-green-400">{winCount}</span>
        </p>
        <p className="flex items-center justify-between text-sm">
          <span className="text-gray-300">Losses</span>
          <span className="font-semibold tabular-nums text-red-400">{lossCount}</span>
        </p>
      </div>
    </div>
  )
}

function SignedColumns({
  points,
  label,
}: {
  points: { key: string; label: string; value: number }[]
  label: (point: { key: string; label: string; value: number }) => string
}) {
  const max = Math.max(1, ...points.map((point) => Math.abs(point.value)))
  return (
    <div className="flex h-36 items-stretch gap-2">
      {points.map((point) => {
        const height =
          point.value === 0 ? 0 : Math.max(8, (Math.abs(point.value) / max) * 100)
        const negative = point.value < 0
        return (
          <div key={point.key} className="flex min-w-0 flex-1 flex-col">
            <div className="relative flex-1">
              <div className="absolute inset-x-0 top-1/2 h-px bg-white/10" />
              <div
                className={`absolute inset-x-1 rounded-sm ${barTone(point.value)} ${
                  negative ? "top-1/2" : "bottom-1/2"
                }`}
                style={{ height: `${height / 2}%` }}
              />
            </div>
            <span className="mt-1 truncate text-center text-[11px] text-gray-400">
              {label(point)}
            </span>
          </div>
        )
      })}
    </div>
  )
}

export default function DashboardDesktopTerminal({
  isPro,
  deferredSectionsReady,
  timeframeLabel,
  propFirmDetails = null,
  totalTrades,
  totalPnL,
  winRate,
  winCount,
  lossCount,
  profitFactor,
  avgRR,
  expectancyData,
  bestDay,
  bestTrade,
  avgWin,
  avgLoss,
  biggestLoss,
  worstDay,
  maxDrawdown,
  showDrawdown,
  bestWinStreak,
  streakData,
  showEquity,
  equityData,
  showSessions,
  sessionBuckets,
  weekdayData,
  hourData,
  longShortPerformance,
  holdTimeStats,
}: DashboardDesktopTerminalProps) {
  const sessionMax = Math.max(
    1,
    ...DASHBOARD_SESSION_DISPLAY_ORDER.map((name) =>
      Math.abs(sessionBuckets[name]?.totalPnL ?? 0)
    )
  )
  const longPnL = longShortPerformance.long?.totalPnL ?? 0
  const shortPnL = longShortPerformance.short?.totalPnL ?? 0
  const sideMax = Math.max(1, Math.abs(longPnL), Math.abs(shortPnL))
  const avgMax = Math.max(1, Math.abs(avgWin), Math.abs(avgLoss))
  const hourPoints = Array.from({ length: 24 }, (_, hour) => ({
    key: String(hour),
    label: formatHour(hour, true),
    value: hourData?.hourlyMap?.[hour] ?? 0,
  }))

  const holdRows = [
    { label: "Average", seconds: holdTimeStats.avgHoldSeconds },
    { label: "Winners", seconds: holdTimeStats.winningAvgHoldSeconds },
    { label: "Losers", seconds: holdTimeStats.losingAvgHoldSeconds },
  ]
  const holdMax = Math.max(
    1,
    ...holdRows.map((row) => row.seconds ?? 0)
  )

  return (
    <div className="tt-dash-desktop-v1">
      {propFirmDetails}

      <div className="tt-dash-hero">
        <Panel className="flex flex-col">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-blue-300">
            Performance
          </p>
          <p className={`mt-2 text-4xl font-semibold tabular-nums tracking-tight ${pnlClass(totalPnL)}`}>
            {formatCurrency(totalPnL)}
          </p>
          <p className="mt-1 text-xs text-gray-400">Net P&amp;L · {timeframeLabel}</p>

          <div className="mt-4">
            <MetricLine label="Win Rate" value={`${winRate.toFixed(1)}%`} />
            <MetricLine
              label="Profit Factor"
              value={formatDecimal(profitFactor)}
              valueClassName={
                profitFactor >= 1 ? "text-green-400" : profitFactor > 0 ? "text-red-400" : "text-white"
              }
            />
            <MetricLine label="Avg RR" value={formatRR(avgRR)} />
            <MetricLine label="Trades" value={totalTrades.toLocaleString()} />
          </div>

          <div className="mt-3 border-t border-white/10 pt-1">
            {isPro ? (
              <>
                <MetricLine
                  label="Best Day"
                  value={formatCurrency(bestDay)}
                  valueClassName={pnlClass(bestDay)}
                />
                {showDrawdown ? (
                  <MetricLine
                    label="Max Drawdown"
                    value={formatCurrency(maxDrawdown)}
                    valueClassName="text-red-400"
                  />
                ) : null}
                <MetricLine
                  label="Largest Win"
                  value={formatCurrency(bestTrade)}
                  valueClassName={pnlClass(bestTrade)}
                />
              </>
            ) : (
              <MetricLine label="Best Win Streak" value={bestWinStreak} />
            )}
          </div>
        </Panel>

        <Panel className="min-w-0">
          {showEquity && deferredSectionsReady ? (
            <DashboardEquityCurve
              variant="hero"
              data={equityData}
              totalTrades={totalTrades}
              timeframeLabel={timeframeLabel}
            />
          ) : showEquity ? (
            <div className="tt-dash-equity-plot animate-pulse rounded-lg bg-black/20" />
          ) : (
            <p className="text-sm text-gray-400">Equity curve is hidden in dashboard settings.</p>
          )}
        </Panel>
      </div>

      {isPro ? (
        <div className="tt-dash-strip tt-dash-kpi">
          <KpiCell
            label="Expectancy"
            value={
              expectancyData ? formatCurrency(expectancyData.expectancy) : "—"
            }
            valueClassName={
              expectancyData
                ? `${pnlClass(expectancyData.expectancy)} text-lg font-semibold tabular-nums`
                : "tt-dash-value"
            }
          />
          <KpiCell
            label="Avg Win"
            value={formatCurrency(avgWin)}
            valueClassName="text-lg font-semibold tabular-nums text-green-400"
          />
          <KpiCell
            label="Avg Loss"
            value={formatCurrency(avgLoss)}
            valueClassName="text-lg font-semibold tabular-nums text-red-400"
          />
          <KpiCell
            label="Avg Hold"
            value={holdLabel(holdTimeStats.avgHoldSeconds)}
          />
          <KpiCell
            label="Worst Trade"
            value={formatCurrency(biggestLoss)}
            valueClassName="text-lg font-semibold tabular-nums text-red-400"
          />
          <KpiCell
            label="Worst Day"
            value={formatCurrency(worstDay)}
            valueClassName="text-lg font-semibold tabular-nums text-red-400"
          />
          {streakData ? (
            <KpiCell
              label="Streak"
              value={`${streakData.currentStreak} ${streakData.currentType ?? ""}`.trim()}
              valueClassName={
                streakData.currentType === "win"
                  ? "text-lg font-semibold tabular-nums text-green-400"
                  : streakData.currentType === "loss"
                    ? "text-lg font-semibold tabular-nums text-red-400"
                    : "tt-dash-value"
              }
            />
          ) : null}
        </div>
      ) : null}

      {isPro ? (
        <>
          <div>
            <SectionTitle>Performance Breakdown</SectionTitle>
            <div className="tt-dash-3">
              <Panel>
                <p className="mb-3 text-sm font-semibold text-white">Win / Loss</p>
                <WinLossRing
                  winRate={winRate}
                  winCount={winCount}
                  lossCount={lossCount}
                />
              </Panel>
              <Panel>
                <p className="mb-3 text-sm font-semibold text-white">Long / Short</p>
                <div className="space-y-4">
                  <HBar
                    label="Long"
                    detail={
                      longShortPerformance.long
                        ? `${longShortPerformance.long.winRate.toFixed(0)}% win`
                        : "No trades"
                    }
                    amount={longPnL}
                    max={sideMax}
                    valueLabel={
                      longShortPerformance.long ? formatCurrency(longPnL) : "—"
                    }
                  />
                  <HBar
                    label="Short"
                    detail={
                      longShortPerformance.short
                        ? `${longShortPerformance.short.winRate.toFixed(0)}% win`
                        : "No trades"
                    }
                    amount={shortPnL}
                    max={sideMax}
                    valueLabel={
                      longShortPerformance.short ? formatCurrency(shortPnL) : "—"
                    }
                  />
                </div>
              </Panel>
              <Panel>
                <p className="mb-3 text-sm font-semibold text-white">Average Win / Loss</p>
                <div className="space-y-4">
                  <HBar
                    label="Avg Win"
                    amount={avgWin}
                    max={avgMax}
                    valueLabel={formatCurrency(avgWin)}
                  />
                  <HBar
                    label="Avg Loss"
                    amount={avgLoss}
                    max={avgMax}
                    valueLabel={formatCurrency(avgLoss)}
                  />
                </div>
              </Panel>
            </div>
          </div>

          <div>
            <SectionTitle>When You Perform Best</SectionTitle>
            <div className="tt-dash-2">
              {showSessions ? (
                <Panel>
                  <p className="mb-3 text-sm font-semibold text-white">
                    Performance by Session
                  </p>
                  <div className="space-y-3">
                    {DASHBOARD_SESSION_DISPLAY_ORDER.map((name) => {
                      const stats = sessionBuckets[name]
                      const pnl = stats?.totalPnL ?? 0
                      return (
                        <HBar
                          key={name}
                          label={sessionLabel(name)}
                          detail={
                            stats?.totalTrades
                              ? `${stats.totalTrades} trades`
                              : "No trades"
                          }
                          amount={pnl}
                          max={sessionMax}
                          valueLabel={stats ? formatCurrency(pnl) : "—"}
                        />
                      )
                    })}
                  </div>
                </Panel>
              ) : null}
              <Panel className={showSessions ? "" : "tt-dash-span-2"}>
                <p className="mb-3 text-sm font-semibold text-white">
                  Performance by Weekday
                </p>
                <SignedColumns
                  points={weekdayData.map((point) => ({
                    key: point.day,
                    label: point.day,
                    value: point.pnl,
                  }))}
                  label={(point) => point.label}
                />
              </Panel>
            </div>
          </div>

          <div>
            <SectionTitle>Trading Behavior</SectionTitle>
            <div className="tt-dash-2">
              <Panel>
                <p className="mb-1 text-sm font-semibold text-white">
                  Performance by Hour
                </p>
                {hourData?.hasValidTradingHoursData ? (
                  <>
                    <SignedColumns
                      points={hourPoints}
                      label={(point) =>
                        Number(point.key) % 6 === 0 ? point.label : ""
                      }
                    />
                    {hourData.bestHour != null && hourData.worstHour != null ? (
                      <p className="mt-2 text-[11px] text-gray-400">
                        Best {formatHour(hourData.bestHour)} · Worst{" "}
                        {formatHour(hourData.worstHour)}
                      </p>
                    ) : null}
                  </>
                ) : (
                  <p className="text-sm text-gray-400">
                    Add entry and exit times to see hourly performance.
                  </p>
                )}
              </Panel>
              <Panel>
                <p className="mb-3 text-sm font-semibold text-white">Hold Time</p>
                {holdTimeStats.hasDurationData ? (
                  <div className="space-y-3">
                    {holdRows.map((row) => (
                      <HBar
                        key={row.label}
                        label={row.label}
                        amount={row.seconds ?? 0}
                        max={holdMax}
                        valueLabel={holdLabel(row.seconds)}
                        neutral
                      />
                    ))}
                  </div>
                ) : (
                  <p className="text-sm text-gray-400">
                    Hold time appears once trades include a duration.
                  </p>
                )}
              </Panel>
            </div>
          </div>
        </>
      ) : null}
    </div>
  )
}
