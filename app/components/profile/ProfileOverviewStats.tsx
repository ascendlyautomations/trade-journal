"use client"

import { formatDecimal, formatProfitFactor, formatRR } from "@/lib/formatDisplay"
import { memo, type ReactNode } from "react"

type ProfileOverviewStatsProps = {
  visible: boolean
  isPrivate: boolean
  totalTrades: number
  winRate: number
  totalPnl: number
  payoutTotal: number | null
  averageRr: number | null
  profitFactor: number | null
  streakLabel: string
}

function formatMoney(value: number) {
  return value < 0
    ? `-$${Math.abs(value).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
    : `$${value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
}

function StatCard({
  label,
  children,
}: {
  label: string
  children: ReactNode
}) {
  return (
    <div className="min-w-0 rounded-xl border border-white/10 bg-white/5 px-1.5 py-1.5 text-center sm:px-2 sm:py-2">
      <p className="truncate text-[10px] text-gray-200 sm:text-[11px] md:text-gray-400">
        {label}
      </p>
      {children}
    </div>
  )
}

function ProfileOverviewStats({
  visible,
  isPrivate,
  totalTrades,
  winRate,
  totalPnl,
  payoutTotal,
  averageRr,
  profitFactor,
  streakLabel,
}: ProfileOverviewStatsProps) {
  return (
    <>
      <div className="grid w-full min-w-0 grid-cols-2 gap-1.5 sm:grid-cols-3 sm:gap-2 lg:grid-cols-4 xl:grid-cols-7">
        <StatCard label="Trades">
          <p className="truncate text-sm font-semibold tabular-nums text-white sm:text-base">
            {visible ? totalTrades : "—"}
          </p>
        </StatCard>
        <StatCard label="Win %">
          <p className="truncate text-sm font-semibold tabular-nums text-white sm:text-base">
            {visible ? `${formatDecimal(winRate)}%` : "—"}
          </p>
        </StatCard>
        <StatCard label="Net P&L">
          <p
            className={`truncate text-sm font-semibold tabular-nums sm:text-base ${
              !visible
                ? "text-white"
                : totalPnl >= 0
                  ? "text-emerald-400"
                  : "text-red-400"
            }`}
          >
            {visible ? formatMoney(totalPnl) : "—"}
          </p>
        </StatCard>
        <StatCard label="Profit Factor">
          <p className="truncate text-sm font-semibold tabular-nums text-white sm:text-base">
            {visible ? formatProfitFactor(profitFactor) : "—"}
          </p>
        </StatCard>
        <StatCard label="Avg RR">
          <p className="truncate text-sm font-semibold tabular-nums text-white sm:text-base">
            {visible ? formatRR(averageRr) : "—"}
          </p>
        </StatCard>
        <StatCard label="Payout Total">
          <p className="truncate text-sm font-semibold tabular-nums text-emerald-400 sm:text-base">
            {payoutTotal != null ? formatMoney(payoutTotal) : "—"}
          </p>
        </StatCard>
        <StatCard label="Streak">
          <p
            className={`truncate text-sm font-semibold tabular-nums sm:text-base ${
              streakLabel.startsWith("W")
                ? "text-emerald-400"
                : streakLabel.startsWith("L")
                  ? "text-red-400"
                  : "text-white"
            }`}
          >
            {streakLabel}
          </p>
        </StatCard>
      </div>

      {!visible && isPrivate ? (
        <p className="text-center text-xs text-gray-300 md:text-gray-400">
          Follow to unlock trading stats in this row.
        </p>
      ) : null}
    </>
  )
}

export default memo(ProfileOverviewStats)
