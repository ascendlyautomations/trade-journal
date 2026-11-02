"use client"

import { useCallback, useRef, type TouchEvent } from "react"
import { isNativeIos } from "@/lib/nativePlatform"
import {
  isPhoneWebTouchTarget,
  shouldDismissSheetFromVerticalDrag,
} from "@/lib/mobileWebTouch"

/**
 * Drag down on a sheet header to dismiss. No-ops on native iOS and ≥768px.
 * Does not call preventDefault, so scrolling and the browser back swipe stay intact.
 */
export function useMobileWebSheetDismiss(onClose: () => void) {
  const onCloseRef = useRef(onClose)
  onCloseRef.current = onClose
  const startX = useRef<number | null>(null)
  const startY = useRef<number | null>(null)

  const onTouchStart = useCallback((event: TouchEvent) => {
    if (isNativeIos() || !isPhoneWebTouchTarget()) return
    startX.current = event.touches[0]?.clientX ?? null
    startY.current = event.touches[0]?.clientY ?? null
  }, [])

  const onTouchEnd = useCallback((event: TouchEvent) => {
    const x0 = startX.current
    const y0 = startY.current
    startX.current = null
    startY.current = null
    if (isNativeIos() || !isPhoneWebTouchTarget()) return
    const x1 = event.changedTouches[0]?.clientX ?? null
    const y1 = event.changedTouches[0]?.clientY ?? null
    if (!shouldDismissSheetFromVerticalDrag(x0, y0, x1, y1)) return
    onCloseRef.current()
  }, [])

  return { onTouchStart, onTouchEnd }
}
