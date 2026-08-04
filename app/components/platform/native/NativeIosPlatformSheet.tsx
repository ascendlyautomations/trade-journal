"use client"

import { useEffect, useState, type ReactNode } from "react"
import { createPortal } from "react-dom"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { cn } from "@/app/components/ui/cn"

export type NativeIosPlatformSheetProps = {
  open: boolean
  onClose: () => void
  title?: string
  ariaLabel?: string
  children: ReactNode
  /** Optional max height class. Default: min(88svh, 640px). */
  maxHeightClassName?: string
  showCloseButton?: boolean
  zIndexClass?: string
}

/**
 * Native iOS bottom sheet chrome for temporary controls (filters, pickers, share).
 * Not fullscreen — presentation only.
 */
export default function NativeIosPlatformSheet({
  open,
  onClose,
  title,
  ariaLabel,
  children,
  maxHeightClassName = "max-h-[min(88svh,640px)]",
  showCloseButton = true,
  zIndexClass = "z-[10050]",
}: NativeIosPlatformSheetProps) {
  const [mounted, setMounted] = useState(false)
  useModalScrollLock(open)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  if (!open || !mounted || typeof document === "undefined") return null

  return createPortal(
    <div
      className={cn(
        "fixed inset-0 flex items-end justify-center",
        zIndexClass
      )}
      role="presentation"
      onClick={onClose}
      data-tt-platform-sheet="native"
    >
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel ?? title ?? "Sheet"}
        className={cn(
          "relative z-10 flex w-full flex-col overflow-hidden rounded-t-2xl border border-white/10 bg-[#0b1f3a] text-white shadow-xl",
          maxHeightClassName
        )}
        style={{ paddingBottom: "var(--safe-area-bottom)" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div
          className="mx-auto mt-2 h-1 w-10 shrink-0 rounded-full bg-white/25"
          aria-hidden
        />
        {(title || showCloseButton) && (
          <div className="flex shrink-0 items-center justify-between border-b border-white/10 px-4 py-3">
            <h2 className="text-base font-semibold text-white">
              {title || "\u00a0"}
            </h2>
            {showCloseButton ? <ModalCloseButton onClick={onClose} /> : null}
          </div>
        )}
        <div className="min-h-0 flex-1 overflow-y-auto">{children}</div>
      </div>
    </div>,
    document.body
  )
}
