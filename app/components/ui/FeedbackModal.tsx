"use client"

import {
  UI_FEEDBACK_MODAL_DISMISS,
  UI_FEEDBACK_MODAL_PANEL_BASE,
  UI_MODAL_BACKDROP,
} from "@/lib/uiPrimitiveStyles"
import { useEffect, useState } from "react"
import { createPortal } from "react-dom"
import { cn } from "./cn"
import ModalCloseButton from "./ModalCloseButton"
import { useModalScrollLock } from "./modalLayout"
import type { FeedbackPopupType } from "./feedback-popup-types"

const panelBorderStyles: Record<FeedbackPopupType, string> = {
  success: "border-positive/50",
  error: "border-negative/50",
  warning: "border-warning/50",
  info: "border-info/50",
}

const messageStyles: Record<FeedbackPopupType, string> = {
  success: "text-positive",
  error: "text-negative",
  warning: "text-warning",
  info: "text-info",
}

/** Above ScrollableModalShell / DetailModalShell overlays (z-[10050]). */
export const FEEDBACK_MODAL_OVERLAY_CLASS =
  "fixed inset-0 z-[10060] flex items-center justify-center p-4 pt-[max(1rem,var(--safe-area-top))] pb-[max(1rem,var(--safe-area-bottom))]"

export type FeedbackModalProps = {
  isOpen: boolean
  message: string
  type?: FeedbackPopupType
  title?: string
  onClose: () => void
  /** Primary dismiss button label (default "Close"). */
  dismissLabel?: string
  /** Extra overlay classes (layout/background). Do not lower z-index. */
  overlayClassName?: string
}

/** Centered TradeTraxs feedback popup (extracted from Settings). */
export default function FeedbackModal({
  isOpen,
  message,
  type = "success",
  title,
  onClose,
  dismissLabel = "Close",
  overlayClassName,
}: FeedbackModalProps) {
  const [mounted, setMounted] = useState(false)
  useModalScrollLock(isOpen)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!isOpen) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [isOpen, onClose])

  if (
    process.env.NODE_ENV !== "production" &&
    isOpen &&
    title === "Getting Started Progress"
  ) {
    console.log("[getting-started] FeedbackModal render", { isOpen, title })
  }

  if (!isOpen || !mounted) return null

  return createPortal(
    <div className={cn(FEEDBACK_MODAL_OVERLAY_CLASS, overlayClassName)}>
      <div className={UI_MODAL_BACKDROP} />
      <div
        className={cn(
          UI_FEEDBACK_MODAL_PANEL_BASE,
          panelBorderStyles[type]
        )}
      >
        <ModalCloseButton
          onClick={onClose}
          className="absolute right-3 top-5 z-10"
        />
        {title ? (
          <h3 className="mb-2 pr-12 text-base font-semibold text-foreground">
            {title}
          </h3>
        ) : null}
        <p
          className={cn(
            "whitespace-pre-line pr-12 text-sm font-medium",
            messageStyles[type]
          )}
        >
          {message}
        </p>
        <button type="button" onClick={onClose} className={UI_FEEDBACK_MODAL_DISMISS}>
          {dismissLabel}
        </button>
      </div>
    </div>,
    document.body
  )
}
