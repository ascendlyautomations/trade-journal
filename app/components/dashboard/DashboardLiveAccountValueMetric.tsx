"use client"

import Link from "next/link"
import { formatCurrency } from "@/lib/formatCurrency"
import { sumManualWithdrawals } from "@/lib/accountPayoutEntry"
import type { DashboardLiveAccountValueState } from "./useDashboardLiveAccountValue"

type DashboardLiveAccountValueMetricProps = {
  state: DashboardLiveAccountValueState
  /** `hero` = desktop terminal; `compact` = mobile stat row */
  variant?: "hero" | "compact"
}

export default function DashboardLiveAccountValueMetric({
  state,
  variant = "hero",
}: DashboardLiveAccountValueMetricProps) {
  if (!state.visible) return null

  if (state.status === "loading") {
    if (variant === "compact") {
      return (
        <div className="col-span-3 rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-center">
          <p className="text-[11px] text-gray-400 md:text-xs">
            Account Value · Loading…
          </p>
        </div>
      )
    }
    return (
      <div className="mt-3 border-t border-white/10 pt-3">
        <p className="text-xs text-gray-400">Account Value · Loading…</p>
      </div>
    )
  }

  if (state.status !== "ready") {
    return null
  }

  const valueClass = state.balance >= 0 ? "text-white" : "text-red-400"
  const withdrawalCount = state.ledgerEntries.length
  const withdrawalTotal = sumManualWithdrawals(state.ledgerEntries)

  const historyLink =
    withdrawalCount > 0 ? (
      <Link
        href="/withdrawals"
        className="mt-1 inline-block text-[11px] text-blue-300 underline-offset-2 hover:underline md:text-xs"
      >
        {withdrawalCount === 1
          ? "1 withdrawal"
          : `${withdrawalCount} withdrawals`}
        {withdrawalTotal > 0
          ? ` (${formatCurrency(withdrawalTotal)}) · View history`
          : " · View history"}
      </Link>
    ) : null

  if (variant === "compact") {
    return (
      <div className="col-span-3 rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-center">
        <p className="text-[11px] text-gray-400 md:text-xs">Account Value</p>
        <p
          className={`text-sm font-semibold tabular-nums md:text-base ${valueClass}`}
        >
          {formatCurrency(state.balance)}
        </p>
        <p className="mt-0.5 text-[10px] text-gray-400 md:text-[11px]">
          Lifetime · all trades &amp; withdrawals
        </p>
        {historyLink}
      </div>
    )
  }

  return (
    <div className="mt-3 border-t border-white/10 pt-3">
      <div className="flex items-baseline justify-between gap-3">
        <span className="tt-dash-label">Account Value</span>
        <span
          className={`text-sm font-semibold tabular-nums ${valueClass}`}
        >
          {formatCurrency(state.balance)}
        </span>
      </div>
      <p className="mt-1 text-[11px] text-gray-400">
        Lifetime tracked balance (starting balance + realized P&amp;L −
        withdrawals). Not affected by the timeframe filter above.
      </p>
      {historyLink}
    </div>
  )
}
