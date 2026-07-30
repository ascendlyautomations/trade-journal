"use client"

import type { ReactNode } from "react"
import {
  dashboardStatLabelClass,
  dashboardWidgetSectionTitleClass,
} from "@/app/components/dashboard/dashboardInsightStyles"
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
  mobileWeekdayPnlSlot: ReactNode
  expectancyData: ExpectancySummary | null
  streakData: StreakSummary | null
  hourData: TradingHoursSummary | null
  showSessions: boolean
  mobileSessionsSlot: ReactNode
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
  subtitle?: string
  className?: string
}) {
  let color = "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"
  const displayValue =
    typeof value === "number"
      ? value.toLocaleString(undefined, {
          minimumFractionDigits: 0,
          maximumFractionDigits: 2,
        })
      : String(value ?? "")

  return (
    <div
      className={`flex h-full min-h-[76px] w-full flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-2.5 text-center backdrop-blur-md ${DASHBOARD_MOBILE_STAT_PAD_CLASS} md:min-h-[90px] md:p-4 ${className}`.trim()}
    >
      <p className={dashboardStatLabelClass}>{title}</p>
      <div className="w-full text-center">
        <span
          className={`block text-center text-sm font-semibold leading-tight whitespace-nowrap tabular-nums md:text-lg lg:text-xl ${color}`}
        >
          {displayValue}
        </span>
        {subtitle ? (
          <p className="mt-0.5 text-[10px] text-gray-400 md:text-xs">{subtitle}</p>
        ) : null}
      </div>
    </div>
  )
}

function bestWinStreakSubtitle(count: number) {
  return count === 1 ? "Winning Trade" : "Winning Trades"
}

function ExpectancyStat({
  expectancyData,
  className,
}: {
  expectancyData: ExpectancySummary | null
  className?: string
}) {
  if (!expectancyData) {
    return (
      <Stat
        title="Expectancy"
        value="—"
        subtitle="Add more trades to unlock this metric."
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
    <div className="flex flex-col gap-2 md:block md:space-y-3">
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:gap-3 lg:grid-cols-1 xl:grid-cols-2">
        <Stat
          title="Net P/L"
          value={formatCurrency(totalPnL)}
          positive={totalPnL >= 0}
        />
        <Stat title="Win Rate" value={`${winRate.toFixed(1)}%`} />
        <Stat
          title="Best Win Streak"
          value={bestWinStreak}
          subtitle={bestWinStreakSubtitle(bestWinStreak)}
        />
        <Stat title="Total Trades" value={formatNumber(totalTrades)} />
        <Stat title="Avg RR" value={formatRR(avgRR)} />
        <Stat
          title="Profit Factor"
          value={formatDecimal(profitFactor)}
          positive={profitFactor >= 1 ? true : profitFactor > 0 ? false : undefined}
        />
      </div>
      {showEquity ? mobileEquitySlot : null}
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
  mobileWeekdayPnlSlot,
  expectancyData,
  streakData,
  hourData,
  showSessions,
  mobileSessionsSlot,
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
      {/* —— Mobile only: one 3×2 metrics grid, then original stacked sections —— */}
      <div className="flex flex-col gap-2 md:hidden">
        <div className="grid grid-cols-3 gap-2">
          <Stat title="Trades" value={formatNumber(totalTrades)} />
          <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />
          <Stat
            title="P&L"
            value={formatCurrency(totalPnL)}
            positive={totalPnL >= 0}
          />
          <ExpectancyStat expectancyData={expectancyData} />
          <Stat
            title="Best Win Streak"
            value={bestWinStreak}
            subtitle={bestWinStreakSubtitle(bestWinStreak)}
          />
          <Stat title="Avg RR" value={formatRR(avgRR)} />
        </div>

        {showEquity ? mobileEquitySlot : null}
        <div>{mobileWeekdayPnlSlot}</div>

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
      </div>

      {/* —— Desktop only: original 2-col metrics grid (unchanged) —— */}
      <div className="hidden md:grid md:grid-cols-2 md:gap-3">
        <Stat title="Trades" value={formatNumber(totalTrades)} />
        <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />
        <Stat
          title="Best Win Streak"
          value={bestWinStreak}
          subtitle={bestWinStreakSubtitle(bestWinStreak)}
        />
        <Stat title="Avg RR" value={formatRR(avgRR)} />
        <Stat
          title="P&L"
          value={formatCurrency(totalPnL)}
          positive={totalPnL >= 0}
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

      <div className={`rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:p-4 ${DASHBOARD_MOBILE_CARD_PAD_CLASS}`}>
        <h3 className={dashboardWidgetSectionTitleClass}>Streaks</h3>

        {streakData ? (
          <>
            <p className="text-xs font-semibold text-white md:text-lg">
              Current: {streakData.currentStreak}{" "}
              <span
                className={
                  streakData.currentType === "win"
                    ? "text-green-400"
                    : streakData.currentType === "loss"
                      ? "text-red-400"
                      : "text-gray-400"
                }
              >
                {streakData.currentType}
              </span>
            </p>

            <div className="mt-1.5 space-y-0.5 text-[10px] text-gray-400 md:mt-2 md:flex md:gap-4 md:space-y-0 md:text-xs">
              <p>Max Wins: {streakData.maxWinStreak}</p>
              <p>Max Losses: {streakData.maxLossStreak}</p>
            </div>
          </>
        ) : (
          <p className="text-[11px] text-gray-400 md:text-sm">
            Upload your first trade to see streak insights.
          </p>
        )}
      </div>

      <div className="block md:hidden">
        {showSessions ? mobileSessionsSlot : null}
      </div>

      <div className={`rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:p-4 ${DASHBOARD_MOBILE_CARD_PAD_CLASS}`}>
        <h3 className={dashboardWidgetSectionTitleClass}>Trading Hours</h3>

        {hourData === null ? (
          <p className="text-[11px] text-gray-400 md:text-sm">
            Complete more trades to view trading hour insights.
          </p>
        ) : !hourData.hasValidTradingHoursData ? (
          <p className="text-xs text-gray-400 md:text-sm">
            Add entry/exit times to unlock trading hour insights
          </p>
        ) : (
          <>
            <p className="text-xs text-green-400 md:text-sm">
              {`Best: ${formatHour(hourData.bestHour!)} (${formatCurrency(hourData.hourlyMap[hourData.bestHour!])})`}
            </p>
            <p className="text-xs text-red-400 md:text-sm">
              {`Worst: ${formatHour(hourData.worstHour!)} (${formatCurrency(hourData.hourlyMap[hourData.worstHour!])})`}
            </p>
          </>
        )}
      </div>

      {maxDrawdownSlot}
    </div>
  )
}
