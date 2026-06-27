"use client"

import type { ReactNode } from "react"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatRR } from "@/lib/formatDisplay"

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
  expectancy:       number
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
  totalTrades: number
  winRate: number
  avgRR: number | null
  totalPnL: number
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
}

function Stat({
  title,
  value,
  positive,
}: {
  title: string
  value: string | number
  positive?: boolean
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
    <div className="flex min-h-[90px] w-full flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-3 text-center backdrop-blur-md md:p-4">
      <p className="text-xs md:text-sm text-gray-300 mb-1">{title}</p>
      <div className="w-full text-center">
        <span
          className={`block font-semibold text-base md:text-lg lg:text-xl text-center leading-tight whitespace-nowrap tabular-nums ${color}`}
        >
          {displayValue}
        </span>
      </div>
    </div>
  )
}

export default function DashboardStatsGrid({
  totalTrades,
  winRate,
  avgRR,
  totalPnL,
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
}: DashboardStatsGridProps) {
  return (
    <div className="flex flex-col gap-4 md:block md:space-y-4">
      <div className="grid grid-cols-2 gap-3 md:gap-3">
        <Stat title="Trades" value={formatNumber(totalTrades)} />
        <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />
        <Stat title="Avg RR" value={formatRR(avgRR)} />
        <Stat
          title="P&L"
          value={formatCurrency(totalPnL)}
          positive={totalPnL >= 0}
        />
        {showEquity ? mobileEquitySlot : null}
        <div className="col-span-2 block md:hidden">{mobileWeekdayPnlSlot}</div>
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

      <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
        <h3 className="text-xs md:text-sm text-gray-300">
          Expectancy
          {expectancyData ? (
            <>
              {" "}
              <span
                className={`font-semibold tabular-nums text-sm md:text-lg ${
                  expectancyData.expectancy >= 0
                    ? "text-green-400"
                    : "text-red-400"
                }`}
              >
                {formatMoney(expectancyData.expectancy)}
              </span>
            </>
          ) : null}
        </h3>

        {!expectancyData ? (
          <p className="mt-2 text-gray-400 text-xs md:text-sm">
            Add more trades to unlock this metric.
          </p>
        ) : null}
      </div>

      <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
        <h3 className="mb-2 text-xs md:text-sm text-gray-300">Streaks</h3>

        {streakData ? (
          <>
            <p className="text-sm md:text-lg font-semibold text-white">
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

            <div className="text-[11px] md:text-xs text-gray-400 mt-2 space-y-1">
              <p>Max Wins: {streakData.maxWinStreak}</p>
              <p>Max Losses: {streakData.maxLossStreak}</p>
            </div>
          </>
        ) : (
          <p className="text-gray-400 text-xs md:text-sm">
            Not enough trading history yet.
          </p>
        )}
      </div>

      <div className="block md:hidden">
        {showSessions ? mobileSessionsSlot : null}
      </div>

      <div className="rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
        <h3 className="mb-2 text-xs md:text-sm text-gray-300">Trading Hours</h3>

        {hourData === null ? (
          <p className="text-gray-400 text-xs md:text-sm">
            Track additional trades to view insights.
          </p>
        ) : !hourData.hasValidTradingHoursData ? (
          <p className="text-white/60 text-sm">
            Add entry/exit times to unlock trading hour insights
          </p>
        ) : (
          <>
            <p className="text-green-400">
              {`Best: ${formatHour(hourData.bestHour!)} (${formatCurrency(hourData.hourlyMap[hourData.bestHour!])})`}
            </p>
            <p className="text-red-400">
              {`Worst: ${formatHour(hourData.worstHour!)} (${formatCurrency(hourData.hourlyMap[hourData.worstHour!])})`}
            </p>
          </>
        )}
      </div>

      {maxDrawdownSlot}
    </div>
  )
}
