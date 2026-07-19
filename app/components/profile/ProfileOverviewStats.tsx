"use client"

import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import { memo } from "react"

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
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6 md:gap-4">
        <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
          <p className="text-xs text-gray-400">Trades</p>
          <p className="text-lg font-semibold tabular-nums text-white">
            {visible ? totalTrades : "—"}
          </p>
        </div>
        <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
          <p className="text-xs text-gray-400">Win %</p>
          <p className="text-lg font-semibold tabular-nums text-white">
            {visible ? `${formatDecimal(winRate)}%` : "—"}
          </p>
        </div>
        <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
          <p className="text-xs text-gray-400">Net P&amp;L</p>
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
        </div>
        <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
          <p className="text-xs text-gray-400">Payout Total</p>
          <p className="text-lg font-semibold tabular-nums text-emerald-400">
            {payoutTotal != null ? formatMoney(payoutTotal) : "—"}
          </p>
        </div>
        <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
          <p className="text-xs text-gray-400">Avg RR</p>
          <p className="text-lg font-semibold tabular-nums text-white">
            {visible ? formatRR(averageRr) : "—"}
          </p>
        </div>
        <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
          <p className="text-xs text-gray-400">Streak</p>
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
        </div>
      </div>

      {!visible && isPrivate ? (
        <p className="text-center text-xs text-gray-400">
          Follow to unlock trading stats in this row.
        </p>
      ) : null}
    </>
  )
}

export default memo(ProfileOverviewStats)
