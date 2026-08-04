"use client"

import { useCallback, useRef, type TouchEvent } from "react"

const SWIPE_THRESHOLD_PX = 48

/**
 * Mobile-only horizontal swipe between adjacent profile trades in the detail modal.
 * Ignores mostly-vertical gestures so comment scrolling is unaffected.
 */
export function useMobileTradeDetailSwipe(options: {
  enabled: boolean
  onPrev: () => void
  onNext: () => void
}) {
  const { enabled, onPrev, onNext } = options
  const startX = useRef<number | null>(null)
  const startY = useRef<number | null>(null)

  const onTouchStart = useCallback(
    (e: TouchEvent) => {
      if (!enabled) return
      startX.current = e.touches[0]?.clientX ?? null
      startY.current = e.touches[0]?.clientY ?? null
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

      const x1 = e.changedTouches[0]?.clientX ?? x0
      const y1 = e.changedTouches[0]?.clientY ?? y0
      const deltaX = x1 - x0
      const deltaY = y1 - y0

      if (Math.abs(deltaX) < SWIPE_THRESHOLD_PX) return
      if (Math.abs(deltaY) > Math.abs(deltaX)) return

      if (deltaX < 0) onNext()
      else onPrev()
    },
    [enabled, onNext, onPrev]
  )

  return { onTouchStart, onTouchEnd }
}
