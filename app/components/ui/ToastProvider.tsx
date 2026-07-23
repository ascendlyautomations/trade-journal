"use client"

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react"
import Toast from "./Toast"
import type { ToastInput, ToastItem, ToastType } from "./toast-types"

const DEFAULT_DURATION = 4000

type ToastContextValue = {
  toast: (input: ToastInput) => string
  success: (message: string, duration?: number) => string
  error: (message: string, duration?: number) => string
  info: (message: string, duration?: number) => string
  warning: (message: string, duration?: number) => string
  dismiss: (id: string) => void
}

const ToastContext = createContext<ToastContextValue | null>(null)

function newToastId() {
  return `toast-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([])

  const dismiss = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id))
  }, [])

  const push = useCallback(
    (message: string, type: ToastType = "info", duration = DEFAULT_DURATION) => {
      const id = newToastId()
      const item: ToastItem = { id, message, type, duration }
      setToasts((prev) => [...prev.slice(-4), item])
      return id
    },
    []
  )

  const value = useMemo<ToastContextValue>(
    () => ({
      toast: (input) =>
        push(input.message, input.type ?? "info", input.duration ?? DEFAULT_DURATION),
      success: (message, duration) => push(message, "success", duration ?? DEFAULT_DURATION),
      error: (message, duration) => push(message, "error", duration ?? DEFAULT_DURATION + 500),
      info: (message, duration) => push(message, "info", duration ?? DEFAULT_DURATION),
      warning: (message, duration) => push(message, "warning", duration ?? DEFAULT_DURATION),
      dismiss,
    }),
    [push, dismiss]
  )

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div
        aria-label="Notifications"
        className="pointer-events-none fixed inset-x-0 bottom-0 z-[10000] flex flex-col items-center gap-2 p-4 pb-[max(1rem,calc(var(--safe-area-bottom)+var(--app-tab-bar-height)))] sm:inset-x-auto sm:right-4 sm:bottom-4 sm:items-end sm:p-0"
      >
        {toasts.map((t) => (
          <Toast key={t.id} toast={t} onDismiss={dismiss} />
        ))}
      </div>
    </ToastContext.Provider>
  )
}

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext)
  if (!ctx) {
    throw new Error("useToast must be used within ToastProvider")
  }
  return ctx
}
