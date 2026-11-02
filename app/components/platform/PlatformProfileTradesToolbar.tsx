"use client"

import type { ReactNode } from "react"
import NativeIosProfileTradesOutcomeFilter, {
  type ProfileTradesOutcomeFilter,
} from "./native/NativeIosProfileTradesOutcomeFilter"
import { usePlatformPresentation } from "./usePlatformPresentation"

export type { ProfileTradesOutcomeFilter }

type PlatformProfileTradesToolbarProps = {
  /** Existing Grid/List toggle — unchanged on both platforms. */
  children: ReactNode
  outcomeFilter: ProfileTradesOutcomeFilter
  onOutcomeFilterChange: (value: ProfileTradesOutcomeFilter) => void
}

/**
 * Profile trades toolbar adapter.
 * Native iOS: All/Wins/Losses capsule (left) + Grid/List (right).
 * Web: Grid/List only, right-aligned as before.
 */
export default function PlatformProfileTradesToolbar({
  children,
  outcomeFilter,
  onOutcomeFilterChange,
}: PlatformProfileTradesToolbarProps) {
  const { isNativeIos } = usePlatformPresentation()

  if (!isNativeIos) {
    return (
      <div className="mb-2 flex items-center justify-between gap-2">
        <div
          className="flex min-h-11 items-center gap-1"
          role="group"
          aria-label="Filter trades by outcome"
        >
          {(["all", "wins", "losses"] as const).map((option) => {
            const selected = outcomeFilter === option
            const label =
              option === "all" ? "All" : option === "wins" ? "Wins" : "Losses"
            return (
              <button
                key={option}
                type="button"
                onClick={() => onOutcomeFilterChange(option)}
                className={`inline-flex h-8 min-w-[3.25rem] items-center justify-center rounded-full px-3 text-[12px] font-semibold ${
                  selected
                    ? "bg-white/15 text-white max-md:bg-surface-elevated max-md:text-foreground"
                    : "bg-transparent text-white/55 max-md:text-muted-foreground"
                }`}
              >
                {label}
              </button>
            )
          })}
        </div>
        <div className="shrink-0">{children}</div>
      </div>
    )
  }

  return (
    <div className="mb-2 flex items-center justify-between gap-2">
      <NativeIosProfileTradesOutcomeFilter
        value={outcomeFilter}
        onChange={onOutcomeFilterChange}
      />
      <div className="shrink-0">{children}</div>
    </div>
  )
}
