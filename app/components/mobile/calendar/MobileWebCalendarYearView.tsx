"use client"

import {
  compactCalendarYearPnl,
  MOBILE_WEB_CALENDAR_MONTH_ABBREV,
  type MobileWebCalendarYearOverview,
} from "@/lib/mobileWebCalendarYear"
import { formatSignedPnlDisplay } from "@/lib/formatDisplay"
import { MOBILE_WEB_CARD_CLASS } from "@/lib/mobileWebPageSurface"

type MobileWebCalendarYearViewProps = {
  overview: MobileWebCalendarYearOverview
  onSelectMonth: (month: number) => void
}

function pnlTone(value: number, empty: boolean) {
  if (empty) return "text-muted-foreground"
  if (value > 0) return "text-emerald-400"
  if (value < 0) return "text-red-400"
  return "text-foreground"
}

function monthFill(value: number, empty: boolean) {
  if (empty) return "bg-white/5"
  if (value > 0) return "bg-emerald-500/15"
  if (value < 0) return "bg-red-500/15"
  return "bg-white/10"
}

export default function MobileWebCalendarYearView({
  overview,
  onSelectMonth,
}: MobileWebCalendarYearViewProps) {
  const bestAbbrev =
    overview.bestMonth != null
      ? MOBILE_WEB_CALENDAR_MONTH_ABBREV[overview.bestMonth - 1]
      : null
  const maxAbs = Math.max(
    ...overview.months.map((m) => Math.abs(m.isFuture ? 0 : m.netPnl)),
    1
  )

  return (
    <div className="flex flex-col gap-3">
      <section className={`${MOBILE_WEB_CARD_CLASS} px-2 py-3`} aria-label="Year summary">
        <p className="mb-2 px-1 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
          Year Summary
        </p>
        <div className="grid grid-cols-4 gap-1">
          <SummaryCell
            label="Year P&L"
            value={formatSignedPnlDisplay(overview.netPnl)}
            tone={pnlTone(overview.netPnl, overview.tradeCount === 0)}
          />
          <SummaryCell label="Trade Days" value={String(overview.tradingDayCount)} />
          <SummaryCell
            label="Win Rate"
            value={
              overview.winRate == null ? "—" : `${overview.winRate.toFixed(0)}%`
            }
          />
          <SummaryCell
            label="Best Month"
            value={
              bestAbbrev && overview.bestMonthPnl != null
                ? `${bestAbbrev} ${compactCalendarYearPnl(overview.bestMonthPnl)}`
                : "—"
            }
            tone={
              overview.bestMonthPnl != null
                ? pnlTone(overview.bestMonthPnl, false)
                : undefined
            }
          />
        </div>
      </section>

      <div className="grid grid-cols-3 gap-1.5">
        {overview.months.map((card) => {
          const empty =
            card.isFuture || (card.tradeCount === 0 && card.tradingDayCount === 0)
          return (
            <button
              key={card.month}
              type="button"
              disabled={card.isFuture}
              onClick={() => onSelectMonth(card.month)}
              className={`flex min-h-14 flex-col items-center justify-center rounded-[12px] px-1 py-2 ${monthFill(
                card.netPnl,
                empty
              )} disabled:opacity-50`}
              aria-label={`${card.abbreviation}, ${compactCalendarYearPnl(card.netPnl)}`}
            >
              <span className="text-[11px] font-semibold text-muted-foreground">
                {card.abbreviation}
              </span>
              <span
                className={`text-[13px] font-semibold tabular-nums ${pnlTone(
                  card.netPnl,
                  empty
                )}`}
              >
                {compactCalendarYearPnl(card.netPnl)}
              </span>
            </button>
          )
        })}
      </div>

      <section className={`${MOBILE_WEB_CARD_CLASS} px-3 py-3`} aria-label="Monthly P&L">
        <p className="mb-3 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
          Monthly P&L
        </p>
        <div className="flex h-[120px] items-end gap-1">
          {overview.months.map((card) => {
            const value = card.isFuture ? 0 : card.netPnl
            const height = Math.max(4, Math.round((Math.abs(value) / maxAbs) * 100))
            return (
              <div key={card.month} className="flex min-w-0 flex-1 flex-col items-center gap-1">
                <div className="flex h-[100px] w-full items-end justify-center">
                  <div
                    className={`w-full max-w-[14px] rounded-t-[3px] ${
                      value > 0
                        ? "bg-emerald-400/90"
                        : value < 0
                          ? "bg-red-400/90"
                          : "bg-white/20"
                    }`}
                    style={{ height: `${height}%` }}
                  />
                </div>
                <span className="text-[9px] text-muted-foreground">
                  {card.abbreviation.charAt(0)}
                </span>
              </div>
            )
          })}
        </div>
      </section>
    </div>
  )
}

function SummaryCell({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone?: string
}) {
  return (
    <div className="min-w-0 px-1 text-center">
      <p className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">
        {label}
      </p>
      <p
        className={`truncate text-[11px] font-semibold tabular-nums ${
          tone ?? "text-foreground"
        }`}
      >
        {value}
      </p>
    </div>
  )
}
