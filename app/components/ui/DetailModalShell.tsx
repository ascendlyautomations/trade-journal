"use client"

import { useCallback, useEffect, type ReactNode } from "react"
import ModalCloseButton from "./ModalCloseButton"

/** Matches Navbar `h-16` / root layout `pt-16`. */
export const NAVBAR_HEIGHT_CLASS = "top-16"
export const NAVBAR_HEIGHT_REM = "4rem"

/**
 * Standard form-modal overlay: anchored below the fixed navbar on all breakpoints.
 * Matches DetailModalShell / FeedStoryViewer — top-aligned, horizontally centered, scrollable.
 */
export const MODAL_FIXED_BELOW_NAVBAR_CLASS =
  "fixed inset-x-0 bottom-0 top-16 flex items-start justify-center overflow-y-auto"

/** @deprecated Use MODAL_FIXED_BELOW_NAVBAR_CLASS */
export const MODAL_OVERLAY_BELOW_NAVBAR_CLASS = MODAL_FIXED_BELOW_NAVBAR_CLASS

/** @deprecated Pass belowNavbar to Modal instead */
export const MODAL_COMPONENT_BELOW_NAVBAR_CLASS = MODAL_FIXED_BELOW_NAVBAR_CLASS

type DetailModalShellProps = {
  ariaLabel: string
  onClose: () => void
  title?: string
  /** Non-scrolling post/trade details (image, meta, actions). */
  details?: ReactNode
  /** Comments region; should use an internal list scroll pane. */
  comments?: ReactNode
  /** Full custom body (e.g. TradeCard with internal scroll split). */
  children?: ReactNode
  /**
   * `split`: wider dialog + two-column body on md+ (media left, panel right).
   * Mobile remains stacked via `splitMedia` placed above `splitPanel`.
   */
  layout?: "default" | "split"
  splitMedia?: ReactNode
  splitPanel?: ReactNode
  /** Hides the stacked mobile media slot when comments are focused. */
  suppressMobileSplitMedia?: boolean
  zIndexClass?: string
  backdropClassName?: string
}

export default function DetailModalShell({
  ariaLabel,
  onClose,
  title,
  details,
  comments,
  children,
  layout = "default",
  splitMedia,
  splitPanel,
  suppressMobileSplitMedia = false,
  zIndexClass = "z-[9000]",
  backdropClassName = "bg-black/70",
}: DetailModalShellProps) {
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [onClose])

  useEffect(() => {
    const html = document.documentElement
    const body = document.body
    const prevHtmlOverflow = html.style.overflow
    const prevBodyOverflow = body.style.overflow
    html.style.overflow = "hidden"
    body.style.overflow = "hidden"
    return () => {
      html.style.overflow = prevHtmlOverflow
      body.style.overflow = prevBodyOverflow
    }
  }, [])

  const stopPropagation = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
  }, [])

  const dialogWidthClass =
    layout === "split"
      ? "max-w-2xl md:max-w-[760px]"
      : "max-w-2xl"

  const body =
    layout === "split" && splitPanel != null ? (
      <div className="flex min-h-0 flex-1 flex-col overflow-hidden md:flex-row">
        {splitMedia ? (
          <div className="hidden md:flex md:min-h-0 md:flex-1 md:items-center md:justify-center md:border-r md:border-white/10 md:bg-black/40 md:p-3">
            {splitMedia}
          </div>
        ) : null}
        <div className="flex min-h-0 flex-1 flex-col overflow-hidden md:w-[400px] md:shrink-0 lg:w-[420px]">
          {splitMedia && !suppressMobileSplitMedia ? (
            <div className="shrink-0 bg-black/30 md:hidden">{splitMedia}</div>
          ) : null}
          <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
            {splitPanel}
          </div>
        </div>
      </div>
    ) : children ? (
      <div className="flex min-h-0 flex-1 flex-col overflow-hidden">{children}</div>
    ) : (
      <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
        {details ? (
          <div className="shrink-0 overflow-hidden">{details}</div>
        ) : null}
        {comments ? (
          <div className="flex min-h-0 flex-1 flex-col overflow-hidden border-t border-white/10">
            {comments}
          </div>
        ) : null}
      </div>
    )

  return (
    <div
      className={`fixed inset-x-0 bottom-0 ${NAVBAR_HEIGHT_CLASS} flex flex-col overflow-hidden p-3 sm:p-4 ${backdropClassName} ${zIndexClass}`}
      onClick={onClose}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel}
        className={`mx-auto flex min-h-0 w-full flex-1 flex-col overflow-hidden rounded-xl bg-[#0f172a] text-gray-100 shadow-xl ${dialogWidthClass}`}
        style={{
          maxHeight: "calc(100dvh - var(--navbar-height, 4rem) - 1.5rem)",
        }}
        onClick={stopPropagation}
      >
        <header className="flex shrink-0 items-center justify-between gap-3 border-b border-white/10 bg-[#0f172a] px-3 py-2.5">
          <p className="min-w-0 truncate text-sm font-semibold text-white">
            {title || "\u00a0"}
          </p>
          <ModalCloseButton onClick={onClose} />
        </header>

        {body}
      </div>
    </div>
  )
}

/** Scroll a modal comments list pane and focus the composer input. */
export function scrollModalCommentsPane(
  container: HTMLElement | null | undefined,
  behavior: ScrollBehavior = "smooth"
) {
  if (!container) return
  container.scrollTo({ top: container.scrollHeight, behavior })
  const input =
    container.parentElement?.querySelector("input") ??
    container.querySelector("input")
  if (input instanceof HTMLInputElement) {
    input.focus()
  }
}
