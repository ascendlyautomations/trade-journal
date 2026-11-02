"use client"

import { formatDecimal, formatProfitFactor } from "@/lib/formatDisplay"

type MobileWebProfileStatsRowProps = {
  visible: boolean
  isPrivate: boolean
  totalTrades: number
  postsCount: number | null
  winRate: number
  payoutTotal: number | null
  profitFactor: number | null
}

function formatPayout(value: number) {
  return value < 0
    ? `-$${Math.abs(value).toLocaleString(undefined, {
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
      })}`
    : `$${value.toLocaleString(undefined, {
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
      })}`
}

function StatColumn({
  label,
  value,
}: {
  label: string
  value: string
}) {
  return (
    <div className="min-w-0 flex-1 text-center">
      <p className="truncate text-[15px] font-semibold tabular-nums text-[color:var(--tt-text,#1f2328)]">
        {value}
      </p>
      <p className="truncate text-[10px] text-[color:var(--tt-text-muted,#57606a)]">
        {label}
      </p>
    </div>
  )
}

export default function MobileWebProfileStatsRow({
  visible,
  isPrivate,
  totalTrades,
  postsCount,
  winRate,
  payoutTotal,
  profitFactor,
}: MobileWebProfileStatsRowProps) {
  return (
    <div className="px-1">
      <div className="flex items-start py-2">
        <StatColumn
          label="Trades"
          value={visible ? totalTrades.toLocaleString() : "—"}
        />
        <StatColumn
          label="Posts"
          value={postsCount == null ? "—" : postsCount.toLocaleString()}
        />
        <StatColumn
          label="Payouts"
          value={payoutTotal != null ? formatPayout(payoutTotal) : "—"}
        />
        <StatColumn
          label="Win %"
          value={visible ? `${formatDecimal(winRate)}%` : "—"}
        />
        <StatColumn
          label="Profit Factor"
          value={visible ? formatProfitFactor(profitFactor) : "—"}
        />
      </div>
      {!visible && isPrivate ? (
        <p className="pb-1 text-center text-[11px] text-[color:var(--tt-text-muted,#57606a)]">
          Follow to unlock trading stats in this row.
        </p>
      ) : null}
    </div>
  )
}
