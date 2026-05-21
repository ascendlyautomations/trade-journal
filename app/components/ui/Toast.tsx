"use client"

import { useEffect, useState } from "react"
import type { ToastItem } from "./toast-types"
import { cn } from "./cn"

const typeStyles: Record<ToastItem["type"], string> = {
  success:
    "border-emerald-500/40 bg-emerald-950/80 text-emerald-100 shadow-[0_0_24px_rgba(16,185,129,0.12)]",
  error:
    "border-red-500/40 bg-red-950/80 text-red-100 shadow-[0_0_24px_rgba(239,68,68,0.12)]",
  info: "border-blue-500/40 bg-[#0f172a]/90 text-blue-100 shadow-lg shadow-black/30",
  warning:
    "border-amber-500/40 bg-amber-950/80 text-amber-100 shadow-[0_0_24px_rgba(245,158,11,0.1)]",
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
        "pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-xl border px-4 py-3 backdrop-blur-md transition-all duration-300 ease-out",
        typeStyles[toast.type],
        visible ? "translate-y-0 opacity-100" : "translate-y-2 opacity-0"
      )}
    >
      <span
        className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-white/10 text-xs font-bold"
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
        className="shrink-0 rounded p-1 text-xs text-white/60 transition hover:bg-white/10 hover:text-white"
        aria-label="Dismiss notification"
      >
        ✕
      </button>
    </div>
  )
}
