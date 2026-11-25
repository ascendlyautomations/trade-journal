"use client"

import { formatDecimal, formatProfitFactor, formatRR } from "@/lib/formatDisplay"
import { memo, type ReactNode } from "react"

type ProfileOverviewStatsProps = {
  visible: boolean
  /** When true, only the four public header metrics are shown (locked private profiles). */
  publicHeaderOnly?: boolean
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
  publicHeaderOnly = false,
  isPrivate,
  totalTrades,
  winRate,
  totalPnl,
  payoutTotal,
  averageRr,
  profitFactor,
  streakLabel,
}: ProfileOverviewStatsProps) {
  const showSummary = visible || publicHeaderOnly

  return (
    <div
      className={`grid w-full min-w-0 gap-1.5 sm:gap-2 ${
        publicHeaderOnly
          ? "grid-cols-2 sm:grid-cols-4"
          : "grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-7"
      }`}
    >
      <StatCard label="Trades">
        <p className="truncate text-sm font-semibold tabular-nums text-white sm:text-base">
          {showSummary ? totalTrades : "—"}
        </p>
      </StatCard>
      <StatCard label="Win %">
        <p className="truncate text-sm font-semibold tabular-nums text-white sm:text-base">
          {showSummary ? `${formatDecimal(winRate)}%` : "—"}
        </p>
      </StatCard>
      {!publicHeaderOnly ? (
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
      ) : null}
      <StatCard label="Profit Factor">
        <p className="truncate text-sm font-semibold tabular-nums text-white sm:text-base">
          {showSummary ? formatProfitFactor(profitFactor) : "—"}
        </p>
      </StatCard>
      {!publicHeaderOnly ? (
        <>
          <StatCard label="Avg RR">
            <p className="truncate text-sm font-semibold tabular-nums text-white sm:text-base">
              {visible ? formatRR(averageRr) : "—"}
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
        </>
      ) : null}
      <StatCard label="Payouts">
        <p className="truncate text-sm font-semibold tabular-nums text-emerald-400 sm:text-base">
          {payoutTotal != null ? formatMoney(payoutTotal) : "—"}
        </p>
      </StatCard>
    </div>
  )
}

export default memo(ProfileOverviewStats)
