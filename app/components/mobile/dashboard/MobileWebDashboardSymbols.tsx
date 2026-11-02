"use client"

import { formatRR, formatSignedPnlDisplay } from "@/lib/formatDisplay"
import { mobileWebBarShare } from "@/lib/mobileWebDashboardAnalytics"
import { mwDashMoneyClass, mwDashText } from "./mobileWebDashboardChrome"

type SymbolPerformanceRow = {
  ticker: string
  totalTrades: number
  wins: number
  winRate: number
  totalPnL: number
  avgRR: number | null
}

export default function MobileWebDashboardSymbols({
  rows,
}: {
  rows: SymbolPerformanceRow[]
}) {
  if (rows.length === 0) return null

  const maxAbs = Math.max(1, ...rows.map((row) => Math.abs(row.totalPnL)))

  return (
    <div className="flex flex-col gap-3">
      {rows.map((row) => {
        const share = mobileWebBarShare(row.totalPnL, maxAbs)
        const barColor =
          row.totalPnL > 0
            ? "var(--tt-positive, #3ddc97)"
            : row.totalPnL < 0
              ? "var(--tt-negative, #ff7b72)"
              : "color-mix(in srgb, var(--tt-text) 18%, transparent)"

        return (
          <div key={row.ticker} className="flex flex-col gap-1">
            <div className="flex min-w-0 items-baseline gap-2">
              <span
                className={`w-[52px] shrink-0 truncate text-[13px] font-semibold tracking-wide ${mwDashText.primary}`}
              >
                {row.ticker}
              </span>
              <span className={`min-w-0 flex-1 text-[11px] tabular-nums ${mwDashText.tertiary}`}>
                {row.totalTrades.toLocaleString()} · {row.winRate.toFixed(0)}% · RR{" "}
                {formatRR(row.avgRR)}
              </span>
              <span
                className={`shrink-0 text-right text-[13px] font-semibold tabular-nums ${mwDashMoneyClass(row.totalPnL)}`}
              >
                {formatSignedPnlDisplay(row.totalPnL)}
              </span>
            </div>
            <div className="flex h-3 items-center">
              <div
                className="h-3 w-full"
                style={{
                  display: "flex",
                  justifyContent: row.totalPnL < 0 ? "flex-end" : "flex-start",
                }}
              >
                <div
                  className="h-3 rounded-[4px]"
                  style={{
                    width: `${share * 100}%`,
                    backgroundColor: barColor,
                  }}
                />
              </div>
            </div>
          </div>
        )
      })}
    </div>
  )
}
