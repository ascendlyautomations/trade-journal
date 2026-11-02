"use client"

import type { MobileWebDashboardChip } from "@/lib/mobileWebDashboard"

type MobileWebDashboardPerformanceGridProps = {
  cards: MobileWebDashboardChip[]
}

function toneClass(tone: MobileWebDashboardChip["tone"]) {
  if (tone === "positive") return "text-emerald-400"
  if (tone === "negative") return "text-red-400"
  return "text-[color:var(--tt-text,#f0f3f6)]"
}

export default function MobileWebDashboardPerformanceGrid({
  cards,
}: MobileWebDashboardPerformanceGridProps) {
  if (cards.length === 0) return null

  return (
    <div className="grid grid-cols-2 gap-2">
      {cards.map((card) => (
        <div
          key={card.id}
          className="rounded-[10px] bg-white/5 px-4 py-3"
        >
          <p className="text-[11px] leading-tight text-[color:var(--tt-text-tertiary,#a8b3c2)]">
            {card.label}
          </p>
          <p
            className={`mt-1 truncate text-[15px] font-semibold leading-tight tabular-nums ${toneClass(card.tone)}`}
          >
            {card.value}
          </p>
        </div>
      ))}
    </div>
  )
}
