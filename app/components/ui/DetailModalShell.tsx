"use client"

import { useCallback, useEffect, type ReactNode } from "react"

/** Matches Navbar `h-16` / root layout `pt-16`. */
export const NAVBAR_HEIGHT_CLASS = "top-16"
export const NAVBAR_HEIGHT_REM = "4rem"

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
        className="mx-auto flex min-h-0 w-full max-w-2xl flex-1 flex-col overflow-hidden rounded-xl bg-[#0f172a] shadow-xl"
        style={{
          maxHeight: "calc(100dvh - var(--navbar-height, 4rem) - 1.5rem)",
        }}
        onClick={stopPropagation}
      >
        <header className="flex shrink-0 items-center justify-between gap-3 border-b border-white/10 bg-[#0f172a] px-3 py-2.5">
          <p className="min-w-0 truncate text-sm font-semibold text-white">
            {title || "\u00a0"}
          </p>
          <button
            type="button"
            onClick={onClose}
            className="shrink-0 rounded-md bg-white/10 px-2.5 py-1.5 text-sm font-medium text-white transition hover:bg-white/20"
            aria-label="Close"
          >
            ✕
          </button>
        </header>

        {children ? (
          <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
            {children}
          </div>
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
        )}
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
