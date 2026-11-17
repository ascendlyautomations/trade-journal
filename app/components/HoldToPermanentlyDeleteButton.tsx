"use client"

import { useCallback, useEffect, useRef, useState } from "react"

const HOLD_MS = 5000

type HoldToPermanentlyDeleteButtonProps = {
  disabled?: boolean
  processing?: boolean
  onHoldComplete: () => void
}

/**
 * Requires continuous press for 5s; releasing, leaving, or blurring resets progress.
 * Does not submit via keyboard Enter or a normal click.
 */
export default function HoldToPermanentlyDeleteButton({
  disabled = false,
  processing = false,
  onHoldComplete,
}: HoldToPermanentlyDeleteButtonProps) {
  const [progress, setProgress] = useState(0)
  const holdStartRef = useRef<number | null>(null)
  const rafRef = useRef<number | null>(null)
  const completedRef = useRef(false)

  const cancelHold = useCallback(() => {
    holdStartRef.current = null
    completedRef.current = false
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
    setProgress(0)
  }, [])

  const tick = useCallback(() => {
    const start = holdStartRef.current
    if (start == null) return
    const elapsed = Date.now() - start
    const next = Math.min(1, elapsed / HOLD_MS)
    setProgress(next)
    if (next >= 1 && !completedRef.current) {
      completedRef.current = true
      cancelHold()
      onHoldComplete()
      return
    }
    rafRef.current = requestAnimationFrame(tick)
  }, [cancelHold, onHoldComplete])

  const beginHold = useCallback(() => {
    if (disabled || processing || completedRef.current) return
    holdStartRef.current = Date.now()
    setProgress(0)
    rafRef.current = requestAnimationFrame(tick)
  }, [disabled, processing, tick])

  useEffect(() => {
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current)
    }
  }, [])

  useEffect(() => {
    const onVisibility = () => {
      if (document.hidden) cancelHold()
    }
    document.addEventListener("visibilitychange", onVisibility)
    return () => document.removeEventListener("visibilitychange", onVisibility)
  }, [cancelHold])

  const blocked = disabled || processing

  return (
    <div
      role="button"
      tabIndex={blocked ? -1 : 0}
      aria-disabled={blocked}
      aria-label="Hold to permanently delete account"
      className={`relative flex h-[52px] w-full select-none items-center justify-center overflow-hidden rounded-lg bg-red-600 text-center font-semibold text-white transition-opacity ${
        blocked ? "cursor-not-allowed opacity-60" : "cursor-pointer"
      }`}
      onPointerDown={(e) => {
        if (blocked || e.button !== 0) return
        e.currentTarget.setPointerCapture(e.pointerId)
        beginHold()
      }}
      onPointerUp={(e) => {
        if (e.currentTarget.hasPointerCapture(e.pointerId)) {
          e.currentTarget.releasePointerCapture(e.pointerId)
        }
        cancelHold()
      }}
      onPointerCancel={cancelHold}
      onPointerLeave={cancelHold}
      onClick={(e) => e.preventDefault()}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") e.preventDefault()
      }}
    >
      <HoldProgressFill progress={progress} />
      <span className="relative z-10 block px-4">
        {processing ? "Deleting…" : "Hold 5 Seconds to Delete"}
      </span>
    </div>
  )
}

function HoldProgressFill({ progress }: { progress: number }) {
  return (
    <span
      aria-hidden
      className="absolute inset-y-0 left-0 bg-red-900/90 transition-[width] duration-75 ease-linear"
      style={{ width: `${progress * 100}%` }}
    />
  )
}