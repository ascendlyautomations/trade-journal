"use client"

import { cn } from "./cn"
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
  onClose: () => void
}

/** Centered TradeTraxs feedback popup (extracted from Settings). */
export default function FeedbackModal({
  isOpen,
  message,
  type = "success",
  onClose,
}: FeedbackModalProps) {
  if (!isOpen) return null

  return (
    <div className="fixed inset-0 flex items-center justify-center z-50">
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />
      <div
        className={cn(
          "relative w-full max-w-sm rounded-xl border px-6 py-5 text-center shadow-xl",
          panelStyles[type]
        )}
      >
        <p className={cn("text-sm font-medium", messageStyles[type])}>{message}</p>
        <button
          type="button"
          onClick={onClose}
          className="mt-4 text-xs text-gray-400 hover:underline"
        >
          Close
        </button>
      </div>
    </div>
  )
}
