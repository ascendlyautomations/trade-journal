"use client"

import type { WeekdayChartPoint } from "@/app/components/dashboard/DashboardWeekdayChart"
import { formatCurrency } from "@/lib/formatCurrency"
import { mobileWebWeekdayCellOpacity } from "@/lib/mobileWebDashboardAnalytics"
import MobileWebDashboardEmptyCopy from "./MobileWebDashboardEmptyCopy"
import { mwDashText } from "./mobileWebDashboardChrome"

type MobileWebDashboardWeekdaysProps = {
  data: WeekdayChartPoint[]
  totalTrades?: number
}

export default function MobileWebDashboardWeekdays({
  data,
  totalTrades = 0,
}: MobileWebDashboardWeekdaysProps) {
  const hasActivity =
    totalTrades > 0 && data.some((point) => Math.abs(point.pnl) > 0.01)

  if (!hasActivity) {
    return (
      <MobileWebDashboardEmptyCopy body="Complete a few more trades to unlock your weekday heatmap." />
    )
  }

  const maxAbs = Math.max(1, ...data.map((point) => Math.abs(point.pnl)))
  const best = data.reduce((lead, point) =>
    point.pnl > lead.pnl ? point : lead
  )
  const worst = data.reduce((lead, point) =>
    point.pnl < lead.pnl ? point : lead
  )
  const showBest = best.pnl > 0.01
  const showWorst = worst.pnl < -0.01

  return (
    <div className="flex flex-col gap-2">
      {showBest || showWorst ? (
        <div className="flex flex-wrap gap-x-3 gap-y-0.5 text-[11px]">
          {showBest ? (
            <span className={mwDashText.positive}>
              Best {best.day} · {formatCurrency(best.pnl)}
            </span>
          ) : null}
          {showWorst ? (
            <span className={mwDashText.negative}>
              Worst {worst.day} · {formatCurrency(worst.pnl)}
            </span>
          ) : null}
        </div>
      ) : null}

      <div className="flex gap-1.5" role="list" aria-label="Weekday results">
        {data.map((point) => {
          const opacity = mobileWebWeekdayCellOpacity(point.pnl, maxAbs)
          const isBest = showBest && point.day === best.day
          const isWorst = showWorst && point.day === worst.day
          const fill =
            opacity === 0
              ? "color-mix(in srgb, var(--tt-text) 8%, transparent)"
              : `color-mix(in srgb, ${
                  point.pnl >= 0
                    ? "var(--tt-positive, #3ddc97)"
                    : "var(--tt-negative, #ff7b72)"
                } ${Math.round(opacity * 100)}%, transparent)`

          return (
            <div
              key={point.day}
              role="listitem"
              aria-label={`${point.day}, ${formatCurrency(point.pnl)}`}
              className="flex min-w-0 flex-1 flex-col items-center gap-1.5"
            >
              <div
                className={`flex h-11 w-full items-center justify-center rounded-[8px] ${
                  isBest || isWorst
                    ? "ring-1 ring-[color:color-mix(in_srgb,var(--tt-text)_45%,transparent)]"
                    : ""
                }`}
                style={{ backgroundColor: fill }}
              >
                <span
                  className={`text-[11px] font-bold ${mwDashText.primary}`}
                  aria-hidden
                >
                  {Math.abs(point.pnl) < 0.01 ? "·" : point.pnl >= 0 ? "+" : "−"}
                </span>
              </div>
              <span className={`text-[11px] ${mwDashText.tertiary}`} aria-hidden>
                {point.day}
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
