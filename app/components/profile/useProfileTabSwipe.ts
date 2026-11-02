"use client"

import { useCallback, useRef, type TouchEvent } from "react"
import {
  adjacentMobileWebProfileTab,
  adjacentProfileTab,
} from "@/lib/profileTabStrip"
import { isLeadingBackGestureZone } from "@/lib/leadingBackGestureZone"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import type { ProfileTab } from "./ProfileTabs"
import { hapticLight } from "@/lib/nativeHaptics"

/** Match native ``FeedContentFilterSwipeSupport`` thresholds. */
const MINIMUM_DISTANCE_PX = 28
const DIRECTION_THRESHOLD_PX = 56
const HORIZONTAL_DOMINANCE_RATIO = 1.35

export function useProfileTabSwipe(options: {
  enabled: boolean
  activeTab: ProfileTab
  onTabChange: (tab: ProfileTab) => void
}) {
  const { enabled, activeTab, onTabChange } = options
  const isNativeIos = useIsNativeIos()
  const startX = useRef<number | null>(null)
  const startY = useRef<number | null>(null)

  const onTouchStart = useCallback(
    (e: TouchEvent) => {
      if (!enabled) return
      const x = e.touches[0]?.clientX ?? null
      const y = e.touches[0]?.clientY ?? null
      startX.current = x
      startY.current = y
    },
    [enabled]
  )

  const onTouchEnd = useCallback(
    (e: TouchEvent) => {
      if (!enabled) return
      const x0 = startX.current
      const y0 = startY.current
      startX.current = null
      startY.current = null
      if (x0 == null || y0 == null) return

      if (isLeadingBackGestureZone(x0)) return

      const x1 = e.changedTouches[0]?.clientX ?? x0
      const y1 = e.changedTouches[0]?.clientY ?? y0
      const deltaX = x1 - x0
      const deltaY = y1 - y0
      const absX = Math.abs(deltaX)
      const absY = Math.abs(deltaY)

      if (Math.max(absX, absY) < MINIMUM_DISTANCE_PX) return
      if (Math.max(absX, absY) < DIRECTION_THRESHOLD_PX) return
      if (absX <= absY * HORIZONTAL_DOMINANCE_RATIO) return

      const neighbor = isNativeIos
        ? adjacentProfileTab
        : adjacentMobileWebProfileTab

      if (deltaX < 0) {
        const next = neighbor(activeTab, 1)
        if (!next) return
        void hapticLight("profile-tab-swipe")
        onTabChange(next)
        return
      }

      const previous = neighbor(activeTab, -1)
      if (!previous) return
      void hapticLight("profile-tab-swipe")
      onTabChange(previous)
    },
    [activeTab, enabled, isNativeIos, onTabChange]
  )

  return { onTouchStart, onTouchEnd }
}
