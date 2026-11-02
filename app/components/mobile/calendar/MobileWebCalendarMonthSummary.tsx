"use client"

import { formatSignedPnlDisplay } from "@/lib/formatDisplay"
import type { PeriodTradeStats } from "@/lib/periodTradeStats"
import { MOBILE_WEB_CARD_CLASS } from "@/lib/mobileWebPageSurface"

function toneClass(value: number | null | undefined) {
  if (value == null || !Number.isFinite(value) || value === 0) {
    return "text-[color:var(--tt-text,#1f2328)]"
  }
  return value > 0 ? "text-emerald-400" : "text-red-400"
}

function Cell({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone?: string
}) {
  return (
    <div className="min-w-0 px-1 py-1 text-center">
      <p className="text-[10px] font-medium uppercase tracking-wide text-[color:var(--tt-text-muted,#57606a)]">
        {label}
      </p>
      <p
        className={`mt-0.5 truncate text-[13px] font-semibold tabular-nums ${
          tone ?? "text-[color:var(--tt-text,#1f2328)]"
        }`}
      >
        {value}
      </p>
    </div>
  )
}

export default function MobileWebCalendarMonthSummary({
  stats,
}: {
  stats: PeriodTradeStats
}) {
  const avg =
    stats.consistency.avgDailyPnl != null &&
    Number.isFinite(stats.consistency.avgDailyPnl)
      ? formatSignedPnlDisplay(stats.consistency.avgDailyPnl)
      : "—"

  return (
    <section
      className={`${MOBILE_WEB_CARD_CLASS} mt-3 px-2 py-3 md:hidden`}
      aria-label="Month summary"
    >
      <p className="mb-2 px-1 text-[10px] font-semibold uppercase tracking-wide text-[color:var(--tt-text-muted,#57606a)]">
        Month Summary
      </p>
      <div className="grid grid-cols-3 gap-1">
        <Cell
          label="Net P&L"
          value={formatSignedPnlDisplay(stats.totalPnl)}
          tone={toneClass(stats.totalPnl)}
        />
        <Cell label="Trades" value={String(stats.totalTrades)} />
        <Cell
          label="Days"
          value={String(stats.consistency.tradingDays)}
        />
        <Cell
          label="Win Days"
          value={String(stats.consistency.greenDays)}
          tone={stats.consistency.greenDays > 0 ? "text-emerald-400" : undefined}
        />
        <Cell
          label="Loss Days"
          value={String(stats.consistency.redDays)}
          tone={stats.consistency.redDays > 0 ? "text-red-400" : undefined}
        />
        <Cell
          label="Avg Day"
          value={avg}
          tone={toneClass(stats.consistency.avgDailyPnl)}
        />
      </div>
    </section>
  )
}
