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
    return <div className="mb-2 flex justify-end">{children}</div>
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
