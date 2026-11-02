"use client"

import type { MobileWebDashboardChip } from "@/lib/mobileWebDashboard"

type MobileWebDashboardMetricStripProps = {
  chips: MobileWebDashboardChip[]
}

function toneClass(tone: MobileWebDashboardChip["tone"]) {
  if (tone === "positive") return "text-emerald-400"
  if (tone === "negative") return "text-red-400"
  return "text-[color:var(--tt-text,#f0f3f6)]"
}

export default function MobileWebDashboardMetricStrip({
  chips,
}: MobileWebDashboardMetricStripProps) {
  if (chips.length === 0) return null

  return (
    <div
      className="flex w-full overflow-hidden rounded-[14px] bg-white/5"
      data-testid="dashboard-mobile-metric-strip"
    >
      {chips.map((chip, index) => (
        <div
          key={chip.id}
          className={`flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 px-0.5 py-2 ${
            index > 0 ? "border-l border-white/10" : ""
          }`}
        >
          <p className="max-w-full text-center text-[9px] leading-[1.15] text-[color:var(--tt-text-tertiary,#a8b3c2)]">
            {chip.label}
          </p>
          <p
            className={`max-w-full truncate text-center text-[12px] font-semibold leading-tight tabular-nums ${toneClass(chip.tone)}`}
          >
            {chip.value}
          </p>
        </div>
      ))}
    </div>
  )
}
