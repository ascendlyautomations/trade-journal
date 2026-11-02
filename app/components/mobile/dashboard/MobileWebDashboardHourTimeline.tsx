"use client"

import { formatCurrency } from "@/lib/formatCurrency"
import {
  mobileWebDashboardHourBars,
  mobileWebDashboardHourBarsHaveSignal,
} from "@/lib/mobileWebDashboard"
import {
  mobileWebBarShare,
  mobileWebHourAxisLabel,
  mobileWebHourClockLabel,
} from "@/lib/mobileWebDashboardAnalytics"
import MobileWebDashboardEmptyCopy from "./MobileWebDashboardEmptyCopy"
import { mwDashMoneyClass, mwDashText } from "./mobileWebDashboardChrome"

type MobileWebDashboardHourTimelineProps = {
  hourlyMap: Record<number, number>
  bestHour: number | null
  worstHour: number | null
}

export default function MobileWebDashboardHourTimeline({
  hourlyMap,
  bestHour,
  worstHour,
}: MobileWebDashboardHourTimelineProps) {
  const bars = mobileWebDashboardHourBars(hourlyMap)
  if (!mobileWebDashboardHourBarsHaveSignal(bars)) {
    return (
      <MobileWebDashboardEmptyCopy body="Add entry and exit times to see hourly performance." />
    )
  }

  const maxAbs = Math.max(1, ...bars.map((bar) => Math.abs(bar.value)))
  const peakHour = bestHour ?? bars.reduce((lead, bar) =>
    Math.abs(bar.value) > Math.abs(lead.value) ? bar : lead
  ).hour
  const peakValue = hourlyMap[peakHour] ?? 0

  return (
    <div className="flex flex-col gap-2.5">
      <div>
        <p className={`text-[11px] ${mwDashText.tertiary}`}>Peak hour</p>
        <p
          className={`mt-0.5 text-[15px] font-semibold tabular-nums ${mwDashMoneyClass(peakValue)}`}
        >
          {mobileWebHourClockLabel(peakHour)} · {formatCurrency(peakValue)}
        </p>
      </div>

      {(bestHour != null || worstHour != null) && (
        <div className="flex flex-wrap gap-x-3 gap-y-0.5 text-[11px]">
          {bestHour != null ? (
            <span className={mwDashText.positive}>
              Best {mobileWebHourClockLabel(bestHour)} ·{" "}
              {formatCurrency(hourlyMap[bestHour] ?? 0)}
            </span>
          ) : null}
          {worstHour != null && worstHour !== bestHour ? (
            <span className={mwDashText.negative}>
              Worst {mobileWebHourClockLabel(worstHour)} ·{" "}
              {formatCurrency(hourlyMap[worstHour] ?? 0)}
            </span>
          ) : null}
        </div>
      )}

      <div className="flex h-[112px] items-end gap-[2px]">
        {bars.map((bar) => {
          const share = mobileWebBarShare(bar.value, maxAbs)
          const height = bar.value === 0 ? 6 : Math.max(14, share * 112)
          const fill =
            bar.value > 0
              ? "var(--tt-positive, #3ddc97)"
              : bar.value < 0
                ? "var(--tt-negative, #ff7b72)"
                : "color-mix(in srgb, var(--tt-text) 16%, transparent)"
          return (
            <div
              key={bar.hour}
              title={`${mobileWebHourClockLabel(bar.hour)} · ${formatCurrency(bar.value)}`}
              className="min-w-0 flex-1 rounded-t-[3px]"
              style={{ height, backgroundColor: fill }}
            />
          )
        })}
      </div>

      <div className={`flex justify-between text-[11px] ${mwDashText.tertiary}`}>
        <span>{mobileWebHourAxisLabel(0)}</span>
        <span>{mobileWebHourAxisLabel(6)}</span>
        <span>{mobileWebHourAxisLabel(12)}</span>
        <span>{mobileWebHourAxisLabel(18)}</span>
        <span>{mobileWebHourAxisLabel(23)}</span>
      </div>
    </div>
  )
}
