"use client"

import { useEffect, useState } from "react"
import type { ShareSendPhase } from "@/lib/shareSuccessDismiss"
import { cn } from "./cn"

export type ShareModalSendButtonProps = {
  phase: ShareSendPhase
  disabled?: boolean
  onClick: () => void
  successLabel?: "Sent" | "Shared"
  className?: string
}

/** Send button with inline success confirmation (Toast emerald palette + fade). */
export default function ShareModalSendButton({
  phase,
  disabled = false,
  onClick,
  successLabel = "Shared",
  className,
}: ShareModalSendButtonProps) {
  const isSuccess = phase === "success"
  const isSending = phase === "sending"
  const [successVisible, setSuccessVisible] = useState(false)

  useEffect(() => {
    if (!isSuccess) {
      setSuccessVisible(false)
      return
    }
    const raf = requestAnimationFrame(() => setSuccessVisible(true))
    return () => cancelAnimationFrame(raf)
  }, [isSuccess])

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled || isSending || isSuccess}
      aria-live="polite"
      className={cn(
        "mt-3 inline-flex w-full items-center justify-center gap-2 rounded p-2 transition-all duration-300 ease-out disabled:cursor-not-allowed",
        isSuccess
          ? "bg-emerald-600 text-emerald-50"
          : "bg-blue-600 hover:bg-blue-700 disabled:opacity-50",
        className
      )}
    >
      {isSuccess ? (
        <>
          <span
            className={cn(
              "flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-white/10 text-xs font-bold transition-opacity duration-300 ease-out",
              successVisible ? "opacity-100" : "opacity-0"
            )}
            aria-hidden
          >
            ✓
          </span>
          <span
            className={cn(
              "font-medium transition-opacity duration-300 ease-out",
              successVisible ? "opacity-100" : "opacity-0"
            )}
          >
            {successLabel}
          </span>
        </>
      ) : isSending ? (
        "Sending…"
      ) : (
        "Send"
      )}
    </button>
  )
}
