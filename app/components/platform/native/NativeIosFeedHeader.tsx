"use client"

import type { FeedMode } from "@/app/components/feed/FeedModeToggle"
import PlatformPageHeader from "@/app/components/platform/PlatformPageHeader"
import NativeIosFeedModeCapsule from "./NativeIosFeedModeCapsule"

type NativeIosFeedHeaderProps = {
  mode: FeedMode
  onModeChange: (mode: FeedMode) => void
}

/** Brand wordmark — Trade (blue) + Traxs (green), matching navbar brand hues. */
function TradeTraxsWordmark() {
  return (
    <h1 className="min-w-0 truncate text-[17px] font-bold tracking-tight">
      <span className="text-blue-400">Trade</span>
      <span className="text-emerald-400">Traxs</span>
    </h1>
  )
}

/**
 * Native Feed header — branded wordmark + compact Following/Global dropdown.
 * Background matches the Feed surface (no contrasting chrome bar).
 */
export default function NativeIosFeedHeader({
  mode,
  onModeChange,
}: NativeIosFeedHeaderProps) {
  return (
    <PlatformPageHeader
      leftContent={<TradeTraxsWordmark />}
      rightActions={
        <NativeIosFeedModeCapsule mode={mode} onModeChange={onModeChange} />
      }
      className="border-b border-white/[0.06] bg-[var(--tt-surface,#1e3a8a)]"
    />
  )
}
