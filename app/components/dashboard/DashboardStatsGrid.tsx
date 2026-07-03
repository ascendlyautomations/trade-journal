"use client"

import type { ReactNode } from "react"
import LockedFeature from "@/app/components/LockedFeature"
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
  isPro?: boolean
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
    <div className="flex min-h-[76px] w-full flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-2.5 text-center backdrop-blur-md md:min-h-[90px] md:p-4">
      <p className="mb-0.5 text-[11px] text-gray-300 md:mb-1 md:text-sm">{title}</p>
      <div className="w-full text-center">
        <span
          className={`block text-center text-sm font-semibold leading-tight whitespace-nowrap tabular-nums md:text-lg lg:text-xl ${color}`}
        >
          {displayValue}
        </span>
      </div>
    </div>
  )
}

export default function DashboardStatsGrid({
  isPro = true,
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
    <div className="flex flex-col gap-3 md:block md:space-y-4">
      <div className="grid grid-cols-2 gap-2 md:gap-3">
        <Stat title="Trades" value={formatNumber(totalTrades)} />
        <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />
        {isPro ? <Stat title="Avg RR" value={formatRR(avgRR)} /> : null}
        <Stat
          title="P&L"
          value={formatCurrency(totalPnL)}
          positive={totalPnL >= 0}
        />
        {!isPro ? (
          <div className="col-span-2">
            <LockedFeature title="Avg RR" className="min-h-[76px] md:min-h-[90px]" />
          </div>
        ) : null}
        {showEquity ? mobileEquitySlot : null}
        {isPro ? (
          <div className="col-span-2 block md:hidden">{mobileWeekdayPnlSlot}</div>
        ) : (
          <div className="col-span-2 block md:hidden">
            <LockedFeature title="Weekday Performance" className="min-h-[220px]" />
          </div>
        )}
        {isPro ? (
          <>
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
          </>
        ) : null}
      </div>

      {isPro ? (
        <>
      <div className="rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:p-4">
        <h3 className="text-[11px] text-gray-300 md:text-sm">
          Expectancy
          {expectancyData ? (
            <>
              {" "}
              <span
                className={`text-xs font-semibold tabular-nums md:text-lg ${
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
          <p className="mt-1.5 text-[11px] text-gray-400 md:mt-2 md:text-sm">
            Add more trades to unlock this metric.
          </p>
        ) : null}
      </div>

      <div className="rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:p-4">
        <h3 className="mb-1.5 text-[11px] text-gray-300 md:mb-2 md:text-sm">Streaks</h3>

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

            <div className="mt-1.5 space-y-0.5 text-[10px] text-gray-400 md:mt-2 md:space-y-1 md:text-xs">
              <p>Max Wins: {streakData.maxWinStreak}</p>
              <p>Max Losses: {streakData.maxLossStreak}</p>
            </div>
          </>
        ) : (
          <p className="text-[11px] text-gray-400 md:text-sm">
            Not enough trading history yet.
          </p>
        )}
      </div>
        </>
      ) : (
        <>
          <LockedFeature title="Expectancy" className="min-h-[120px]" />
          <LockedFeature title="Trading Hours" className="min-h-[120px]" />
        </>
      )}

      <div className="block md:hidden">
        {showSessions ? (
          isPro ? (
            mobileSessionsSlot
          ) : (
            <LockedFeature title="Session Performance" className="min-h-[220px]" />
          )
        ) : null}
      </div>

      {isPro ? (
      <div className="rounded-xl border border-white/10 bg-white/10 p-2.5 backdrop-blur-md md:p-4">
        <h3 className="mb-1.5 text-[11px] text-gray-300 md:mb-2 md:text-sm">Trading Hours</h3>

        {hourData === null ? (
          <p className="text-[11px] text-gray-400 md:text-sm">
            Track additional trades to view insights.
          </p>
        ) : !hourData.hasValidTradingHoursData ? (
          <p className="text-xs text-white/60 md:text-sm">
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
      ) : null}

      {isPro ? maxDrawdownSlot : <LockedFeature title="Max Drawdown" className="min-h-[120px]" />}
    </div>
  )
}
