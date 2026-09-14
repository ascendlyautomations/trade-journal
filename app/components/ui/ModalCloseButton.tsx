"use client"

import { UI_MODAL_CLOSE_BUTTON } from "@/lib/uiPrimitiveStyles"
import { cn } from "./cn"

export const MODAL_CLOSE_BUTTON_CLASS = UI_MODAL_CLOSE_BUTTON

export type ModalCloseButtonProps = {
  onClick: () => void
  disabled?: boolean
  className?: string
  /** Defaults to "Close". */
  "aria-label"?: string
}

/** Standard top-right dismiss control for TradeTraxs modals and popups. */
export default function ModalCloseButton({
  onClick,
  disabled = false,
  className,
  "aria-label": ariaLabel = "Close",
}: ModalCloseButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={cn(MODAL_CLOSE_BUTTON_CLASS, className)}
      aria-label={ariaLabel}
    >
      ✕
    </button>
  )
}
