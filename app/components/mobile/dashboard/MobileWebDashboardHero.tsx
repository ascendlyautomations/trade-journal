"use client"

import { formatCurrency } from "@/lib/formatCurrency"
import { formatSignedPnlDisplay } from "@/lib/formatDisplay"

type MobileWebDashboardHeroProps = {
  title: string
  periodTitle: string
  tradeCount: number
  displayValue: number | null
  netPnL: number
}

export default function MobileWebDashboardHero({
  title,
  periodTitle,
  tradeCount,
  displayValue,
  netPnL,
}: MobileWebDashboardHeroProps) {
  const heroText =
    displayValue == null ? "—" : formatCurrency(displayValue)
  const netText = formatSignedPnlDisplay(netPnL)
  const netPositive = netPnL >= 0
  const tradeLabel = `${tradeCount.toLocaleString()} ${
    tradeCount === 1 ? "trade" : "trades"
  }`

  return (
    <div className="px-0.5" data-tt-tour-target="dashboardPerformance">
      <div className="flex items-baseline gap-1.5 text-[13px] leading-tight text-[color:var(--tt-text-muted,#c0cad6)]">
        <span>{title}</span>
        <span className="text-[color:var(--tt-text-tertiary,#a8b3c2)]">·</span>
        <span>{periodTitle || "—"}</span>
        <span className="ml-auto shrink-0 text-[12px] tabular-nums text-[color:var(--tt-text-tertiary,#a8b3c2)]">
          {tradeLabel}
        </span>
      </div>
      <p className="mt-1 text-[clamp(1.75rem,11vw,2.5rem)] font-bold leading-none tracking-tight tabular-nums text-[color:var(--tt-text,#f0f3f6)]">
        {heroText}
      </p>
      <div className="mt-2 flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
        <span
          className={`text-[19px] font-semibold tabular-nums leading-none ${
            netPositive ? "text-emerald-400" : "text-red-400"
          }`}
        >
          {netText}
        </span>
        <span className="text-[13px] text-[color:var(--tt-text-muted,#c0cad6)]">
          Net P&amp;L
        </span>
      </div>
    </div>
  )
}
