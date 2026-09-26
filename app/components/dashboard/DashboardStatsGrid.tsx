"use client"

import type { ReactNode } from "react"
import { dashboardMobileNestedLabelClass } from "@/app/components/dashboard/dashboardInsightStyles"
import {
  DASHBOARD_MOBILE_CARD_PAD_CLASS,
  DASHBOARD_MOBILE_STAT_PAD_CLASS,
} from "@/app/components/dashboard/dashboardMobileUi"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatDecimal, formatRR } from "@/lib/formatDisplay"

function formatNumber(value: number) {
  if (value === null || value === undefined) return "-"
  return value.toLocaleString()
}

function formatMoney(v: number) {
  const abs = Math.abs(v)
  const formatted = abs.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  return v < 0 ? `-$${formatted}` : `$${formatted}`
}

/** 0 → 12 AM, 13 → 1 PM (12-hour clock labels). */
function formatHour(h: number) {
  const suffix = h >= 12 ? "PM" : "AM"
  const hour12 = h % 12 || 12
  return `${hour12} ${suffix}`
}

type ExpectancySummary = {
  expectancy: number
}

type StreakSummary = {
  currentStreak: number
  currentType: "win" | "loss" | "even" | null
  maxWinStreak: number
  maxLossStreak: number
}

type TradingHoursSummary = {
  hourlyMap: Record<number, number>
  hasValidTradingHoursData: boolean
  bestHour: number | null
  worstHour: number | null
}

export type DashboardStatsGridProps = {
  isPro?: boolean
  totalTrades: number
  winRate: number
  avgRR: number | null
  totalPnL: number
  profitFactor?: number
  avgWin: number
  bestTrade: number
  avgLoss: number
  biggestLoss: number
  bestDay: number
  worstDay: number
  showEquity: boolean
  mobileEquitySlot: ReactNode
  /** @deprecated Mobile weekday lives in Analytics tab; ignored on mobile. */
  mobileWeekdayPnlSlot?: ReactNode
  expectancyData: ExpectancySummary | null
  streakData: StreakSummary | null
  hourData: TradingHoursSummary | null
  showSessions: boolean
  /** @deprecated Mobile sessions live in Analytics tab; ignored on mobile. */
  mobileSessionsSlot?: ReactNode
  maxDrawdownSlot?: ReactNode
  /** Longest consecutive winning streak (from streakData.maxWinStreak). */
  bestWinStreak: number
}

function Stat({
  title,
  value,
  positive,
  subtitle,
  className = "",
}: {
  title: string
  value: string | number
  positive?: boolean
  subtitle?: ReactNode
  className?: string
}) {
  let color = "tt-dash-value"
  if (positive === true) color = "tt-dash-value tt-dash-value-pos"
  if (positive === false) color = "tt-dash-value tt-dash-value-neg"
  const displayValue =
    typeof value === "number"
      ? value.toLocaleString(undefined, {
          minimumFractionDigits: 0,
          maximumFractionDigits: 2,
        })
      : String(value ?? "")

  return (
    <div
      className={`tt-dash-chip flex h-full min-h-[44px] w-full flex-col items-center justify-center gap-0 p-2.5 text-center ${DASHBOARD_MOBILE_STAT_PAD_CLASS} md:min-h-[72px] md:gap-0 md:p-3 ${className}`.trim()}
    >
      <p className="tt-dash-label max-md:mb-0 max-md:whitespace-nowrap max-md:leading-none">
        {title}
      </p>
      <div className="w-full text-center max-md:leading-none">
        <span
          className={`block text-center text-sm font-semibold leading-tight whitespace-nowrap md:text-base ${color}`}
        >
          {displayValue}
        </span>
        {subtitle ? (
          <p className="mt-0.5 text-[10px] leading-tight text-gray-200 max-md:mt-0 md:text-xs md:text-gray-400">
            {subtitle}
          </p>
        ) : null}
      </div>
    </div>
  )
}

function StripStat({
  title,
  value,
  positive,
}: {
  title: string
  value: string | number
  positive?: boolean
}) {
  let color = "tt-dash-value"
  if (positive === true) color = "tt-dash-value tt-dash-value-pos"
  if (positive === false) color = "tt-dash-value tt-dash-value-neg"
  const displayValue =
    typeof value === "number"
      ? value.toLocaleString(undefined, {
          minimumFractionDigits: 0,
          maximumFractionDigits: 2,
        })
      : String(value ?? "")

  return (
    <div className="tt-dash-strip-cell">
      <p className="tt-dash-label">{title}</p>
      <p className={color}>{displayValue}</p>
    </div>
  )
}

function bestWinStreakSubtitle(count: number) {
  return count === 1 ? "Winning Trade" : "Winning Trades"
}

function streakStatusLabel(type: StreakSummary["currentType"]) {
  if (type === "win") return "Win"
  if (type === "loss") return "Loss"
  if (type === "even") return "Even"
  return "—"
}

function streakTypeAccentClass(
  type: StreakSummary["currentType"]
): string {
  if (type === "win") return "text-green-400"
  if (type === "loss") return "text-red-400"
  return "text-gray-400"
}

function ExpectancyStat({
  expectancyData,
  className,
  /** Mobile top metrics: omit empty-state subtitle so row height stays compact. */
  dense = false,
}: {
  expectancyData: ExpectancySummary | null
  className?: string
  dense?: boolean
}) {
  if (!expectancyData) {
    return (
      <Stat
        title="Expectancy"
        value="—"
        subtitle={
          dense ? undefined : "Add more trades to unlock this metric."
        }
        className={className}
      />
    )
  }

  return (
    <Stat
      title="Expectancy"
      value={formatMoney(expectancyData.expectancy)}
      positive={expectancyData.expectancy >= 0}
      className={className}
    />
  )
}

export function DashboardRecordsStatsGrid({
  avgWin,
  bestTrade,
  avgLoss,
  biggestLoss,
  bestDay,
  worstDay,
}: Pick<
  DashboardStatsGridProps,
  | "avgWin"
  | "bestTrade"
  | "avgLoss"
  | "biggestLoss"
  | "bestDay"
  | "worstDay"
>) {
  return (
    <div className="grid grid-cols-2 gap-2">
      <Stat title="Avg Win" value={formatCurrency(avgWin)} positive />
      <Stat
        title="Best Trade"
        value={formatCurrency(bestTrade)}
        positive={bestTrade >= 0}
      />
      <Stat
        title="Avg Loss"
        value={formatCurrency(avgLoss)}
        positive={false}
      />
      <Stat
        title="Big Loss"
        value={formatCurrency(biggestLoss)}
        positive={false}
      />
      <Stat title="Best Day" value={formatCurrency(bestDay)} positive />
      <Stat
        title="Worst Day"
        value={formatCurrency(worstDay)}
        positive={false}
      />
    </div>
  )
}

export function DashboardStreaksCard({
  streakData,
  bestWinStreak,
}: {
  streakData: StreakSummary | null
  bestWinStreak?: number
}) {
  const resolvedBest =
    bestWinStreak ?? streakData?.maxWinStreak ?? 0

  return (
    <div
      className={`tt-dash-chip p-2.5 md:p-4 ${DASHBOARD_MOBILE_CARD_PAD_CLASS}`}
    >
      <h3 className="tt-dash-section-title mb-2">Streaks</h3>

      {streakData ? (
        <>
          {/* Mobile: single 4-column row — equal cards, Recent Trades surface */}
          <div className="grid grid-cols-4 gap-2 md:hidden">
            <MobileStreakRecentStat
              title="Best Win"
              value={formatNumber(resolvedBest)}
            />
            <MobileStreakRecentStat
              title="Current"
              value={formatNumber(streakData.currentStreak)}
              subtitle={
                <span className={streakTypeAccentClass(streakData.currentType)}>
                  {streakStatusLabel(streakData.currentType)}
                </span>
              }
            />
            <MobileStreakRecentStat
              title="Max Wins"
              value={formatNumber(streakData.maxWinStreak)}
            />
            <MobileStreakRecentStat
              title="Max Losses"
              value={formatNumber(streakData.maxLossStreak)}
            />
          </div>

          {/* Desktop: unchanged */}
          <p className="hidden text-xs font-semibold text-white md:block md:text-lg">
            Current: {streakData.currentStreak}{" "}
            <span className={streakTypeAccentClass(streakData.currentType)}>
              {streakData.currentType}
            </span>
          </p>

          <div className="mt-2 hidden gap-4 text-xs text-gray-400 md:flex">
            <p>Max Wins: {streakData.maxWinStreak}</p>
            <p>Max Losses: {streakData.maxLossStreak}</p>
          </div>
        </>
      ) : (
        <p className="text-[11px] text-gray-300 md:text-sm md:text-gray-400">
          Upload your first trade to see streak insights.
        </p>
      )}
    </div>
  )
}

/**
 * Mobile streak cell — identical surface to Recent Trades trade rows:
 * `rounded-lg border border-white/10 bg-white/5 p-2.5 text-xs`
 */
function MobileStreakRecentStat({
  title,
  value,
  subtitle,
}: {
  title: string
  value: ReactNode
  subtitle?: ReactNode
}) {
  return (
    <div className="tt-dash-chip flex h-full min-h-0 flex-col items-center justify-center p-2.5 text-center text-xs">
      <p className={`leading-tight ${dashboardMobileNestedLabelClass}`}>
        {title}
      </p>
      <p className="mt-0.5 text-sm font-semibold tabular-nums leading-tight text-white">
        {value}
      </p>
      {subtitle ? (
        <p className="mt-0.5 text-[10px] leading-tight text-gray-200">
          {subtitle}
        </p>
      ) : (
        /* Reserve subtitle line so all four cards share equal height */
        <p className="mt-0.5 text-[10px] leading-tight opacity-0" aria-hidden>
          —
        </p>
      )}
    </div>
  )
}

export function DashboardTradingHoursCard({
  hourData,
}: {
  hourData: TradingHoursSummary | null
}) {
  return (
    <div
      className={`tt-dash-chip p-2.5 max-md:px-2 max-md:pb-1.5 max-md:pt-1.5 md:p-4 ${DASHBOARD_MOBILE_CARD_PAD_CLASS}`}
    >
      <h3 className="tt-dash-section-title mb-2 max-md:mb-1">Trading Hours</h3>

      {hourData === null ? (
        <p className="text-[11px] text-gray-200 md:text-sm md:text-gray-400">
          Complete more trades to view trading hour insights.
        </p>
      ) : !hourData.hasValidTradingHoursData ? (
        <p className="text-xs text-gray-200 md:text-sm md:text-gray-400">
          Add entry/exit times to unlock trading hour insights
        </p>
      ) : (
        <div className="max-md:space-y-0.5">
          <p className="text-xs text-green-400 md:text-sm">
            {`Best Hour: ${formatHour(hourData.bestHour!)} · ${formatCurrency(hourData.hourlyMap[hourData.bestHour!])}`}
          </p>
          <p className="text-xs text-red-400 md:text-sm">
            {`Worst Hour: ${formatHour(hourData.worstHour!)} · ${formatCurrency(hourData.hourlyMap[hourData.worstHour!])}`}
          </p>
        </div>
      )}
    </div>
  )
}

function FreeDashboardKpis({
  totalTrades,
  winRate,
  avgRR,
  totalPnL,
  profitFactor = 0,
  bestWinStreak,
  showEquity,
  mobileEquitySlot,
}: Pick<
  DashboardStatsGridProps,
  | "totalTrades"
  | "winRate"
  | "avgRR"
  | "totalPnL"
  | "profitFactor"
  | "bestWinStreak"
  | "showEquity"
  | "mobileEquitySlot"
>) {
  return (
    <div className="flex flex-col gap-2 md:space-y-3">
      <div className="tt-dash-strip tt-dash-hide-desktop-v1 flex">
        <StripStat
          title="Net P/L"
          value={formatCurrency(totalPnL)}
          positive={totalPnL >= 0}
        />
        <StripStat title="Win Rate" value={`${winRate.toFixed(1)}%`} />
        <StripStat title="Trades" value={formatNumber(totalTrades)} />
        <StripStat title="Avg RR" value={formatRR(avgRR)} />
        <StripStat
          title="Profit Factor"
          value={formatDecimal(profitFactor)}
          positive={
            profitFactor >= 1 ? true : profitFactor > 0 ? false : undefined
          }
        />
      </div>
      <Stat
        title="Best Win Streak"
        value={bestWinStreak}
        subtitle={bestWinStreakSubtitle(bestWinStreak)}
        className="tt-dash-hide-desktop-v1"
      />
      {showEquity ? <div className="md:hidden">{mobileEquitySlot}</div> : null}
    </div>
  )
}

export default function DashboardStatsGrid({
  isPro = true,
  totalTrades,
  winRate,
  avgRR,
  totalPnL,
  profitFactor = 0,
  avgWin,
  bestTrade,
  avgLoss,
  biggestLoss,
  bestDay,
  worstDay,
  showEquity,
  mobileEquitySlot,
  expectancyData,
  streakData,
  hourData,
  maxDrawdownSlot,
  bestWinStreak,
}: DashboardStatsGridProps) {
  if (!isPro) {
    return (
      <FreeDashboardKpis
        totalTrades={totalTrades}
        winRate={winRate}
        avgRR={avgRR}
        totalPnL={totalPnL}
        profitFactor={profitFactor}
        bestWinStreak={bestWinStreak}
        showEquity={showEquity}
        mobileEquitySlot={mobileEquitySlot}
      />
    )
  }

  return (
    <div className="flex flex-col gap-2 md:block md:space-y-3">
      {/* Mobile: hero metrics + equity only (tabbed sections render below). */}
      <div className="flex flex-col gap-2 md:hidden">
        <div className="grid grid-cols-3 gap-2">
          <Stat title="Trades" value={formatNumber(totalTrades)} />
          <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />
          <Stat
            title="P&L"
            value={formatCurrency(totalPnL)}
            positive={totalPnL >= 0}
          />
          <ExpectancyStat expectancyData={expectancyData} dense />
          {/*
            No subtitle on mobile — a second line made this cell taller and
            stretched Expectancy / Avg RR via h-full, looking like extra padding.
          */}
          <Stat title="Best Win Streak" value={bestWinStreak} />
          <Stat title="Avg RR" value={formatRR(avgRR)} />
        </div>

        {showEquity ? mobileEquitySlot : null}
      </div>

      <div className="tt-dash-strip tt-dash-hide-desktop-v1 hidden md:flex">
        <StripStat
          title="P&L"
          value={formatCurrency(totalPnL)}
          positive={totalPnL >= 0}
        />
        <StripStat title="Win %" value={`${winRate.toFixed(1)}%`} />
        <StripStat title="Trades" value={formatNumber(totalTrades)} />
        <StripStat title="Avg RR" value={formatRR(avgRR)} />
        <StripStat
          title="Profit Factor"
          value={formatDecimal(profitFactor)}
          positive={
            profitFactor >= 1 ? true : profitFactor > 0 ? false : undefined
          }
        />
      </div>
      <div className="tt-dash-hide-desktop-v1 hidden md:block">
        <p className="tt-dash-section-title">Performance</p>
        <p className="tt-dash-section-subtitle mb-2">
          Outcome quality for this period
        </p>
      </div>
      <div className="tt-dash-hide-desktop-v1 hidden md:grid md:grid-cols-2 md:gap-3">
        <Stat
          title="Best Win Streak"
          value={bestWinStreak}
          subtitle={bestWinStreakSubtitle(bestWinStreak)}
        />
        <ExpectancyStat expectancyData={expectancyData} />
        <Stat title="Avg Win" value={formatCurrency(avgWin)} positive />
        <Stat
          title="Best Trade"
          value={formatCurrency(bestTrade)}
          positive={bestTrade >= 0}
        />
        <Stat title="Avg Loss" value={formatCurrency(avgLoss)} positive={false} />
        <Stat
          title="Big Loss"
          value={formatCurrency(biggestLoss)}
          positive={false}
        />
        <Stat title="Best Day" value={formatCurrency(bestDay)} positive />
        <Stat title="Worst Day" value={formatCurrency(worstDay)} positive={false} />
      </div>

      {/* Desktop column: streaks / hours / drawdown stay in the left rail. */}
      <div className="tt-dash-hide-desktop-v1 hidden md:block md:space-y-3">
        <DashboardStreaksCard streakData={streakData} />
        <DashboardTradingHoursCard hourData={hourData} />
        {maxDrawdownSlot}
      </div>
    </div>
  )
}
