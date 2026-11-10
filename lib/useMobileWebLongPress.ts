"use client"

import { useCallback, useRef, type TouchEvent } from "react"

const DEFAULT_MS = 380
const MOVE_CANCEL_PX = 12

type Options = {
  onLongPress: () => void
  disabled?: boolean
  delayMs?: number
}

/**
 * Long-press for phone web message actions (matches native ~0.38s).
 */
export function useMobileWebLongPress({
  onLongPress,
  disabled = false,
  delayMs = DEFAULT_MS,
}: Options) {
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const startRef = useRef<{ x: number; y: number } | null>(null)
  const firedRef = useRef(false)

  const clearTimer = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current)
      timerRef.current = null
    }
  }, [])

  const onTouchStart = useCallback(
    (e: TouchEvent) => {
      if (disabled) return
      firedRef.current = false
      const t = e.touches[0]
      if (!t) return
      startRef.current = { x: t.clientX, y: t.clientY }
      clearTimer()
      timerRef.current = setTimeout(() => {
        firedRef.current = true
        onLongPress()
      }, delayMs)
    },
    [clearTimer, delayMs, disabled, onLongPress]
  )

  const onTouchMove = useCallback(
    (e: TouchEvent) => {
      if (disabled || !startRef.current) return
      const t = e.touches[0]
      if (!t) return
      const dx = Math.abs(t.clientX - startRef.current.x)
      const dy = Math.abs(t.clientY - startRef.current.y)
      if (dx > MOVE_CANCEL_PX || dy > MOVE_CANCEL_PX) {
        clearTimer()
        startRef.current = null
      }
    },
    [clearTimer, disabled]
  )

  const onTouchEnd = useCallback(() => {
    clearTimer()
    startRef.current = null
  }, [clearTimer])

  const onTouchCancel = useCallback(() => {
    clearTimer()
    startRef.current = null
  }, [clearTimer])

  const suppressClickAfterLongPress = useCallback(() => {
    if (!firedRef.current) return
    firedRef.current = false
  }, [])

  return {
    handlers: {
      onTouchStart,
      onTouchMove,
      onTouchEnd,
      onTouchCancel,
    },
    suppressClickAfterLongPress,
  }
}
