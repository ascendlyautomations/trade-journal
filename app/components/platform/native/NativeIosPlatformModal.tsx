"use client"

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type TouchEvent,
} from "react"
import { createPortal } from "react-dom"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import {
  DETAIL_MODAL_Z_INDEX_CLASS,
  useModalScrollLock,
  useStackedModalEscape,
} from "@/app/components/ui/modalLayout"
import { cn } from "@/app/components/ui/cn"
import { hapticLight } from "@/lib/nativeHaptics"

export type NativeIosPlatformModalProps = {
  /** When false, renders nothing. Defaults to true (call site mounts when open). */
  open?: boolean
  onClose: () => void
  ariaLabel: string
  title?: string
  /** Replaces the default title row label (close button still shown unless hidden). */
  header?: ReactNode
  children: ReactNode
  footer?: ReactNode
  showCloseButton?: boolean
  closeDisabled?: boolean
  /** Vertical swipe-down on the header to dismiss. Default true. */
  swipeToDismiss?: boolean
  zIndexClass?: string
  bodyClassName?: string
  footerClassName?: string
  className?: string
}

/**
 * Native iOS fullscreen modal chrome — full viewport, safe areas, no navbar offset.
 * Presentation only; callers keep their existing content trees.
 */
export default function NativeIosPlatformModal({
  open = true,
  onClose,
  ariaLabel,
  title,
  header,
  children,
  footer,
  showCloseButton = true,
  closeDisabled = false,
  swipeToDismiss = true,
  zIndexClass = DETAIL_MODAL_Z_INDEX_CLASS,
  bodyClassName,
  footerClassName,
  className,
}: NativeIosPlatformModalProps) {
  const [mounted, setMounted] = useState(false)
  const [entered, setEntered] = useState(false)
  const touchStartY = useRef<number | null>(null)
  const [dragY, setDragY] = useState(0)

  useModalScrollLock(open)
  useStackedModalEscape(open && !closeDisabled, onClose)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open) {
      setEntered(false)
      setDragY(0)
      return
    }
    const id = requestAnimationFrame(() => {
      requestAnimationFrame(() => setEntered(true))
    })
    return () => cancelAnimationFrame(id)
  }, [open])

  const handleClose = useCallback(() => {
    if (closeDisabled) return
    hapticLight("modal-close")
    onClose()
  }, [closeDisabled, onClose])

  const onTouchStart = useCallback(
    (e: TouchEvent) => {
      if (!swipeToDismiss || closeDisabled) return
      touchStartY.current = e.touches[0]?.clientY ?? null
    },
    [swipeToDismiss, closeDisabled]
  )

  const onTouchMove = useCallback(
    (e: TouchEvent) => {
      if (!swipeToDismiss || closeDisabled || touchStartY.current == null) return
      const y = e.touches[0]?.clientY
      if (y == null) return
      const dy = Math.max(0, y - touchStartY.current)
      setDragY(dy)
    },
    [swipeToDismiss, closeDisabled]
  )

  const onTouchEnd = useCallback(() => {
    if (!swipeToDismiss || closeDisabled) {
      touchStartY.current = null
      setDragY(0)
      return
    }
    if (dragY > 96) {
      handleClose()
    }
    touchStartY.current = null
    setDragY(0)
  }, [swipeToDismiss, closeDisabled, dragY, handleClose])

  if (!open || !mounted || typeof document === "undefined") return null

  const translateY = entered ? dragY : typeof window !== "undefined" ? window.innerHeight : 800
  const opacity = entered ? Math.max(0.35, 1 - dragY / 400) : 0

  return createPortal(
    <div
      className={cn(
        "fixed inset-0 flex flex-col bg-[#0f172a] text-gray-100",
        zIndexClass,
        className
      )}
      style={{
        transform: `translateY(${translateY}px)`,
        opacity,
        transition:
          dragY > 0
            ? "none"
            : "transform 280ms cubic-bezier(0.32, 0.72, 0, 1), opacity 200ms ease-out",
      }}
      role="dialog"
      aria-modal="true"
      aria-label={ariaLabel}
      data-tt-platform-modal="native"
    >
      <div
        className="flex shrink-0 items-center justify-between gap-3 border-b border-white/10 bg-[#0f172a] px-3 pb-2.5"
        style={{ paddingTop: "max(0.625rem, var(--safe-area-top))" }}
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
        onTouchCancel={onTouchEnd}
      >
        {swipeToDismiss ? (
          <div
            className="absolute left-1/2 top-[max(0.35rem,calc(var(--safe-area-top)-0.15rem))] h-1 w-10 -translate-x-1/2 rounded-full bg-white/25"
            aria-hidden
          />
        ) : null}
        <div className="min-w-0 flex-1 pr-2">
          {header != null ? (
            header
          ) : (
            <p className="truncate text-base font-semibold text-white">
              {title || "\u00a0"}
            </p>
          )}
        </div>
        {showCloseButton ? (
          <ModalCloseButton
            onClick={handleClose}
            disabled={closeDisabled}
            className="relative z-10"
          />
        ) : null}
      </div>

      <div
        className={cn(
          "flex min-h-0 flex-1 flex-col overflow-hidden",
          bodyClassName
        )}
      >
        {children}
      </div>

      {footer ? (
        <div
          className={cn(
            "shrink-0 border-t border-white/10 bg-[#0f172a]",
            footerClassName
          )}
          style={{
            paddingBottom: "max(0.75rem, var(--safe-area-bottom))",
          }}
        >
          {footer}
        </div>
      ) : (
        <div
          className="shrink-0"
          style={{ height: "var(--safe-area-bottom)" }}
          aria-hidden
        />
      )}
    </div>,
    document.body
  )
}
