"use client"

import { useCallback, useEffect, useRef, useState } from "react"

/** Brief confirmation before auto-dismissing share modals (500–750ms target). */
export const SHARE_SUCCESS_DISMISS_MS = 600

export type ShareSendPhase = "idle" | "sending" | "success"

export function useShareSuccessDismiss(
  onClose: () => void,
  delayMs: number = SHARE_SUCCESS_DISMISS_MS
) {
  const [phase, setPhase] = useState<ShareSendPhase>("idle")
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const clearTimer = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current)
      timerRef.current = null
    }
  }, [])

  useEffect(() => clearTimer, [clearTimer])

  const reset = useCallback(() => {
    clearTimer()
    setPhase("idle")
  }, [clearTimer])

  const markSending = useCallback(() => {
    clearTimer()
    setPhase("sending")
  }, [clearTimer])

  const markSuccessAndDismiss = useCallback(() => {
    clearTimer()
    setPhase("success")
    timerRef.current = setTimeout(() => {
      timerRef.current = null
      onClose()
      setPhase("idle")
    }, delayMs)
  }, [clearTimer, delayMs, onClose])

  const isBusy = phase === "sending" || phase === "success"

  return { phase, isBusy, markSending, markSuccessAndDismiss, reset }
}
