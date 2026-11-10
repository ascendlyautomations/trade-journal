"use client"

import { useCallback, useRef, type ReactNode, type TouchEvent } from "react"
import type { FeedContentFilter } from "./feedPostHelpers"
import { usePhoneWebTouchTarget } from "@/lib/usePhoneWebTouchTarget"
import {
  FEED_FILTER_SWIPE_MIN_DISTANCE_PX,
  resolveFeedContentFilterSwipe,
} from "@/lib/feedContentFilterSwipe"

type Props = {
  filter: FeedContentFilter
  onSelect: (next: FeedContentFilter) => void
  disabled?: boolean
  children: ReactNode
  className?: string
}

/**
 * Phone web: horizontal swipe between feed content filters (native parity).
 */
export default function FeedContentFilterSwipeSurface({
  filter,
  onSelect,
  disabled = false,
  children,
  className,
}: Props) {
  const phoneWeb = usePhoneWebTouchTarget()
  const startRef = useRef<{ x: number; y: number } | null>(null)
  const trackingRef = useRef(false)

  const onTouchStart = useCallback(
    (e: TouchEvent) => {
      if (!phoneWeb || disabled) return
      const t = e.touches[0]
      if (!t) return
      trackingRef.current = true
      startRef.current = { x: t.clientX, y: t.clientY }
    },
    [disabled, phoneWeb]
  )

  const onTouchMove = useCallback(
    (e: TouchEvent) => {
      if (!trackingRef.current || !startRef.current) return
      const t = e.touches[0]
      if (!t) return
      const dx = t.clientX - startRef.current.x
      const dy = t.clientY - startRef.current.y
      if (Math.abs(dx) > FEED_FILTER_SWIPE_MIN_DISTANCE_PX && Math.abs(dx) > Math.abs(dy) * 1.1) {
        /* horizontal — don't steal vertical scroll once clearly horizontal */
      }
    },
    []
  )

  const onTouchEnd = useCallback(
    (e: TouchEvent) => {
      if (!phoneWeb || disabled || !trackingRef.current || !startRef.current) return
      trackingRef.current = false
      const t = e.changedTouches[0]
      if (!t) return
      const next = resolveFeedContentFilterSwipe(
        startRef.current.x,
        startRef.current.y,
        t.clientX,
        t.clientY,
        filter
      )
      startRef.current = null
      if (!next || next === filter) return
      void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
        hapticLight("selection")
      })
      onSelect(next)
    },
    [disabled, filter, onSelect, phoneWeb]
  )

  const onTouchCancel = useCallback(() => {
    trackingRef.current = false
    startRef.current = null
  }, [])

  if (!phoneWeb) {
    return <div className={className}>{children}</div>
  }

  return (
    <div
      className={className}
      onTouchStart={onTouchStart}
      onTouchMove={onTouchMove}
      onTouchEnd={onTouchEnd}
      onTouchCancel={onTouchCancel}
    >
      {children}
    </div>
  )
}
