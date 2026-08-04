"use client"

import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import { memo, type ReactNode } from "react"

type ProfileOverviewStatsProps = {
  visible: boolean
  isPrivate: boolean
  totalTrades: number
  winRate: number
  totalPnl: number
  payoutTotal: number | null
  averageRr: number | null
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
    <div className="rounded-xl border border-white/10 bg-white/5 px-2 py-2 text-center md:p-4">
      <p className="text-xs text-gray-200 md:text-gray-400">{label}</p>
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
  streakLabel,
}: ProfileOverviewStatsProps) {
  return (
    <>
      {/* Mobile: 3×2 dense grid (Dashboard gap-2). md+: 3 cols, xl: 6. */}
      <div className="grid grid-cols-3 gap-2 md:grid-cols-3 md:gap-4 xl:grid-cols-6">
        <StatCard label="Trades">
          <p className="text-lg font-semibold tabular-nums text-white">
            {visible ? totalTrades : "—"}
          </p>
        </StatCard>
        <StatCard label="Win %">
          <p className="text-lg font-semibold tabular-nums text-white">
            {visible ? `${formatDecimal(winRate)}%` : "—"}
          </p>
        </StatCard>
        <StatCard label="Net P&L">
          <p
            className={`text-lg font-semibold tabular-nums ${
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
        <StatCard label="Avg RR">
          <p className="text-lg font-semibold tabular-nums text-white">
            {visible ? formatRR(averageRr) : "—"}
          </p>
        </StatCard>
        <StatCard label="Payout Total">
          <p className="text-lg font-semibold tabular-nums text-emerald-400">
            {payoutTotal != null ? formatMoney(payoutTotal) : "—"}
          </p>
        </StatCard>
        <StatCard label="Streak">
          <p
            className={`text-lg font-semibold tabular-nums ${
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
