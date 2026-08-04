"use client"

import { useEffect, useState, type ReactNode } from "react"
import { createPortal } from "react-dom"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { cn } from "@/app/components/ui/cn"

export type NativeIosPlatformDialogProps = {
  open: boolean
  onClose: () => void
  title?: string
  ariaLabel?: string
  children: ReactNode
  footer?: ReactNode
  showCloseButton?: boolean
  closeDisabled?: boolean
  zIndexClass?: string
}

/**
 * Native iOS confirmation dialog — centered card, safe-area padding, no navbar offset.
 */
export default function NativeIosPlatformDialog({
  open,
  onClose,
  title,
  ariaLabel,
  children,
  footer,
  showCloseButton = true,
  closeDisabled = false,
  zIndexClass = "z-[10050]",
}: NativeIosPlatformDialogProps) {
  const [mounted, setMounted] = useState(false)
  useModalScrollLock(open)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open || closeDisabled) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose, closeDisabled])

  if (!open || !mounted || typeof document === "undefined") return null

  return createPortal(
    <div
      className={cn(
        "fixed inset-0 flex items-center justify-center px-6",
        zIndexClass
      )}
      style={{
        paddingTop: "max(1rem, var(--safe-area-top))",
        paddingBottom: "max(1rem, var(--safe-area-bottom))",
      }}
      role="presentation"
      onClick={closeDisabled ? undefined : onClose}
      data-tt-platform-dialog="native"
    >
      <div className="absolute inset-0 bg-black/55 backdrop-blur-sm" aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel ?? title ?? "Dialog"}
        className="relative z-10 w-full max-w-sm overflow-hidden rounded-2xl border border-white/15 bg-[#0f172a] text-gray-100 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        {(title || showCloseButton) && (
          <div className="flex items-start justify-between gap-3 border-b border-white/10 px-5 py-4">
            {title ? (
              <h2 className="text-lg font-semibold text-white">{title}</h2>
            ) : (
              <span />
            )}
            {showCloseButton ? (
              <ModalCloseButton
                onClick={onClose}
                disabled={closeDisabled}
                className="shrink-0"
              />
            ) : null}
          </div>
        )}
        <div className="px-5 py-4">{children}</div>
        {footer ? (
          <div className="border-t border-white/10 px-5 py-4">{footer}</div>
        ) : null}
      </div>
    </div>,
    document.body
  )
}
