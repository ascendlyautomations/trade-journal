"use client"

import { cn } from "./cn"

export const MODAL_CLOSE_BUTTON_CLASS =
  "inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-md bg-white/10 px-2.5 py-1.5 text-sm font-medium text-white opacity-90 transition hover:bg-white/20 hover:opacity-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 disabled:cursor-not-allowed disabled:opacity-50 md:h-auto md:w-auto md:min-h-0 md:min-w-0"

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
