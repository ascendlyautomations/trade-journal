"use client"

import { cn } from "./cn"
import ModalCloseButton from "./ModalCloseButton"
import { useModalScrollLock } from "./modalLayout"
import type { FeedbackPopupType } from "./feedback-popup-types"

const panelStyles: Record<FeedbackPopupType, string> = {
  success: "border-green-500 bg-green-900/20",
  error: "border-red-500 bg-red-900/20",
  warning: "border-amber-500 bg-amber-900/20",
  info: "border-blue-500 bg-blue-900/20",
}

const messageStyles: Record<FeedbackPopupType, string> = {
  success: "text-green-400",
  error: "text-red-400",
  warning: "text-amber-400",
  info: "text-blue-400",
}

export type FeedbackModalProps = {
  isOpen: boolean
  message: string
  type?: FeedbackPopupType
  title?: string
  onClose: () => void
  /** Primary dismiss button label (default "Close"). */
  dismissLabel?: string
  /** Override stacking (e.g. z-[1200] above onboarding import modal). */
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
  useModalScrollLock(isOpen)

  if (
    process.env.NODE_ENV !== "production" &&
    isOpen &&
    title === "Getting Started Progress"
  ) {
    console.log("[getting-started] FeedbackModal render", { isOpen, title })
  }

  if (!isOpen) return null

  return (
    <div
      className={cn(
        "fixed inset-0 z-50 flex items-center justify-center",
        overlayClassName
      )}
    >
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />
      <div
        className={cn(
          "relative w-full max-w-sm rounded-xl border px-6 py-5 text-center shadow-xl",
          panelStyles[type]
        )}
      >
        <ModalCloseButton
          onClick={onClose}
          className="absolute right-3 top-3 z-10"
        />
        {title ? (
          <h3 className="mb-2 pr-10 text-base font-semibold text-white">{title}</h3>
        ) : null}
        <p
          className={cn(
            "whitespace-pre-line text-sm font-medium",
            messageStyles[type]
          )}
        >
          {message}
        </p>
        <button
          type="button"
          onClick={onClose}
          className="mt-4 rounded-lg border border-white/20 bg-white/10 px-4 py-2 text-sm font-medium text-white hover:bg-white/15"
        >
          {dismissLabel}
        </button>
      </div>
    </div>
  )
}
