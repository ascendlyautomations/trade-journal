"use client"

import { MOBILE_WEB_CARD_CLASS } from "@/lib/mobileWebPageSurface"
import {
  formatMoneyUnknown,
  formatNumberUnknown,
  formatRR,
  formatSignedPnlDisplay,
} from "@/lib/formatDisplay"
import { hasStoredRr } from "@/lib/tradeRr"
import { hasStoredTradePoints } from "@/lib/resolveTradePoints"
import {
  computeActualPoints,
  formatSignedPoints,
  resolveRealizedRr,
} from "@/lib/tradePointsAndRealizedRr"
import { resolveTradeDurationLabel } from "@/lib/tradeTimingDisplay"
import { storedPlannedDollarRisk } from "@/lib/plannedTradeRisk"
import {
  tradeExecutionClockLabel,
  tradeExecutionDateLabel,
} from "@/lib/tradeSocialDetailDisplay"

function StatCell({
  label,
  value,
  tone,
  subtitle,
  subtitleLine2,
}: {
  label: string
  value: string
  tone?: string
  subtitle?: string | null
  subtitleLine2?: string | null
}) {
  return (
    <div className="min-w-0">
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
        {label}
      </p>
      <p
        className={`truncate text-[13px] font-semibold tabular-nums ${
          tone ?? "text-foreground"
        }`}
      >
        {value}
      </p>
      {subtitle ? (
        <p className="truncate text-[10px] text-muted-foreground">{subtitle}</p>
      ) : null}
      {subtitleLine2 ? (
        <p className="truncate text-[10px] text-muted-foreground tabular-nums">
          {subtitleLine2}
        </p>
      ) : null}
    </div>
  )
}

export default function PublicSocialTradeStatsPanel({ trade }: { trade: any }) {
  const pnl = Number(trade.pnl)
  const pnlPositive = Number.isFinite(pnl) ? pnl >= 0 : true
  const pnlLabel = Number.isFinite(pnl) ? formatSignedPnlDisplay(pnl) : "—"
  const rrLabel = hasStoredRr(trade.rr) ? formatRR(trade.rr) : null
  const pointsTargeted = hasStoredTradePoints(trade.points)
    ? Number(trade.points)
    : null
  const actualPoints = computeActualPoints(trade)
  const realizedRr = resolveRealizedRr(trade)
  const plannedRisk = storedPlannedDollarRisk(trade.dollar_risk)
  const plannedRiskLabel =
    plannedRisk != null
      ? formatMoneyUnknown(plannedRisk, { empty: "—" })
      : null
  const duration = resolveTradeDurationLabel(trade)
  const entryDate = tradeExecutionDateLabel(trade.entry_time ?? trade.created_at)
  const entryClock = tradeExecutionClockLabel(trade.entry_time)
  const exitDate = tradeExecutionDateLabel(trade.exit_time)
  const exitClock = tradeExecutionClockLabel(trade.exit_time)

  return (
    <div className={`${MOBILE_WEB_CARD_CLASS} rounded-[18px] px-3 py-3`}>
      <div className="grid grid-cols-3 gap-3">
        <StatCell
          label="P&L"
          value={pnlLabel}
          tone={pnlPositive ? "text-emerald-400" : "text-red-400"}
        />
        <StatCell label="Targeted R:R" value={rrLabel ?? "—"} />
        <StatCell
          label="Contracts"
          value={formatNumberUnknown(
            trade.contracts ?? trade.quantity ?? trade.size,
            "—"
          )}
        />
      </div>
      <div className="my-2.5 h-px bg-white/10" />
      <div className="grid grid-cols-3 gap-3">
        <StatCell
          label="Points Targeted"
          value={formatSignedPoints(pointsTargeted)}
        />
        <StatCell
          label="Actual Points"
          value={formatSignedPoints(actualPoints)}
        />
        <StatCell
          label="Realized R:R"
          value={realizedRr != null ? formatRR(realizedRr) : "—"}
        />
      </div>
      {hasStoredRr(trade.max_rr_reached) ? (
        <>
          <div className="my-2.5 h-px bg-white/10" />
          <StatCell label="Max R:R Reached" value={formatRR(trade.max_rr_reached)} />
        </>
      ) : null}
      {plannedRiskLabel ? (
        <>
          <div className="my-2.5 h-px bg-white/10" />
          <StatCell label="Planned Risk ($)" value={plannedRiskLabel} />
        </>
      ) : null}
      <div className="my-2.5 h-px bg-white/10" />
      <div className="grid grid-cols-3 gap-3">
        <StatCell
          label="Entry"
          value={formatMoneyUnknown(trade.entry_price ?? trade.entry, {
            empty: "—",
          })}
          subtitle={entryDate}
          subtitleLine2={entryClock}
        />
        <StatCell
          label="Exit"
          value={formatMoneyUnknown(trade.exit_price ?? trade.exit, {
            empty: "—",
          })}
          subtitle={exitDate}
          subtitleLine2={exitClock}
        />
        <StatCell label="Duration" value={duration ?? "—"} />
      </div>
    </div>
  )
}
