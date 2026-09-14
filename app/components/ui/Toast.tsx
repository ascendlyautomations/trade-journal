"use client"

import {
  UI_TOAST_BASE,
  UI_TOAST_DISMISS,
  UI_TOAST_ERROR,
  UI_TOAST_INFO,
  UI_TOAST_SUCCESS,
  UI_TOAST_WARNING,
} from "@/lib/uiPrimitiveStyles"
import { useEffect, useState } from "react"
import type { ToastItem } from "./toast-types"
import { cn } from "./cn"

const typeStyles: Record<ToastItem["type"], string> = {
  success: UI_TOAST_SUCCESS,
  error: UI_TOAST_ERROR,
  info: UI_TOAST_INFO,
  warning: UI_TOAST_WARNING,
}

const typeIcon: Record<ToastItem["type"], string> = {
  success: "✓",
  error: "✕",
  info: "i",
  warning: "!",
}

type ToastProps = {
  toast: ToastItem
  onDismiss: (id: string) => void
}

export default function Toast({ toast, onDismiss }: ToastProps) {
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    const enter = requestAnimationFrame(() => setVisible(true))
    return () => cancelAnimationFrame(enter)
  }, [])

  useEffect(() => {
    const timer = window.setTimeout(() => onDismiss(toast.id), toast.duration)
    return () => window.clearTimeout(timer)
  }, [toast.id, toast.duration, onDismiss])

  return (
    <div
      role="status"
      aria-live="polite"
      className={cn(
        UI_TOAST_BASE,
        typeStyles[toast.type],
        visible ? "translate-y-0 opacity-100" : "translate-y-2 opacity-0"
      )}
    >
      <span
        className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-surface-elevated text-xs font-bold text-foreground"
        aria-hidden
      >
        {typeIcon[toast.type]}
      </span>
      <p className="min-w-0 flex-1 text-sm leading-snug whitespace-pre-wrap">
        {toast.message}
      </p>
      <button
        type="button"
        onClick={() => onDismiss(toast.id)}
        className={UI_TOAST_DISMISS}
        aria-label="Dismiss notification"
      >
        ✕
      </button>
    </div>
  )
}
