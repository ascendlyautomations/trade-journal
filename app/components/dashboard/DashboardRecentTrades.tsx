"use client"

import Link from "next/link"
import { memo } from "react"
import EmptyState from "@/app/components/ui/EmptyState"
import ExpandableText from "@/app/components/ui/ExpandableText"
import { dashboardInsightCardClass, dashboardInsightTitleClass } from "./dashboardInsightStyles"
import type { DashboardTradeRow } from "./dashboardTypes"
import { formatEST } from "@/lib/formatEST"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatRR } from "@/lib/formatDisplay"

type DashboardRecentTradesProps = {
  trades: DashboardTradeRow[]
  hasAnyTrades: boolean
  onSelectTrade: (trade: DashboardTradeRow) => void
}

function DashboardRecentTrades({
  trades,
  hasAnyTrades,
  onSelectTrade,
}: DashboardRecentTradesProps) {
  return (
    <div className={`h-full ${dashboardInsightCardClass}`}>
      <h3 className={dashboardInsightTitleClass}>Recent Trades</h3>

      <div className="max-h-[28rem] space-y-2 overflow-y-auto pr-1 md:space-y-3">
        {trades.length === 0 ? (
          <EmptyState
            icon="📋"
            title="No recent trades"
            description="Your latest trades will appear here once you log activity."
            action={
              !hasAnyTrades ? (
                <div className="flex flex-wrap items-center justify-center gap-2">
                  <Link
                    href="/app"
                    className="rounded-lg bg-blue-500 px-3 py-1.5 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:hover:bg-blue-500"
                  >
                    + Add Trade
                  </Link>
                  <Link
                    href="/import"
                    className="rounded-lg border border-white/20 bg-white/10 px-3 py-1.5 text-sm font-semibold text-white transition hover:bg-white/15"
                  >
                    Import CSV
                  </Link>
                </div>
              ) : undefined
            }
            className="border-0 bg-transparent py-6"
          />
        ) : (
          trades.map((trade) => (
            <div
              key={trade.id}
              role="button"
              tabIndex={0}
              onClick={() => onSelectTrade(trade)}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault()
                  onSelectTrade(trade)
                }
              }}
              className="w-full cursor-pointer rounded-lg border border-white/10 bg-white/5 p-2.5 text-left text-xs transition hover:bg-white/[0.07] md:p-3 md:text-sm"
            >
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0 space-y-0.5 md:space-y-1">
                  <p className="truncate text-sm font-semibold text-white md:text-base">
                    {trade.ticker}
                    {trade.direction ? (
                      <span className="font-normal text-gray-300">
                        {" "}
                        • {trade.direction}
                      </span>
                    ) : null}
                  </p>
                  <p
                    className={`font-semibold tabular-nums ${
                      (Number(trade.pnl) || 0) >= 0
                        ? "text-green-400"
                        : "text-red-400"
                    }`}
                  >
                    {formatCurrency(Number(trade.pnl) || 0)}
                  </p>
                  <p className="text-[11px] text-gray-300 md:text-xs">
                    RR{" "}
                    {trade.rr != null && trade.rr !== ""
                      ? formatRR(trade.rr)
                      : "—"}
                  </p>
                  <p className="text-[10px] text-gray-400 md:text-xs">
                    {formatEST(String(trade.created_at ?? ""))}
                  </p>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-1">
                  {String(trade.mode ?? trade.account_type ?? "")
                    .toLowerCase()
                    .trim() === "backtest" ? (
                    <span className="rounded-md bg-blue-500/80 px-1.5 py-0.5 text-[10px] font-medium text-white md:px-2 md:py-1 md:text-xs">
                      Backtest
                    </span>
                  ) : null}
                  {trade.public_description ? (
                    <span className="rounded-md bg-green-500/20 px-1.5 py-0.5 text-[10px] font-medium text-green-400 md:px-2 md:py-1 md:text-xs">
                      Posted
                    </span>
                  ) : (
                    <span className="rounded-md bg-white/10 px-1.5 py-0.5 text-[10px] font-medium text-gray-300 md:px-2 md:py-1 md:text-xs">
                      Private
                    </span>
                  )}
                </div>
              </div>
              {trade.public_description ? (
                <ExpandableText
                  className="mt-1.5 text-xs text-gray-200 md:mt-2 md:text-sm"
                  textClassName="text-gray-200"
                  stopPropagation
                >
                  {trade.public_description}
                </ExpandableText>
              ) : null}
              {trade.strategy ? (
                <p className="mt-1 text-[10px] text-gray-300 md:text-xs">
                  Strategy: {trade.strategy}
                </p>
              ) : null}
            </div>
          ))
        )}
      </div>
    </div>
  )
}

export default memo(DashboardRecentTrades)
