"use client"

import { useEffect, useState, type ReactNode } from "react"
import { createPortal } from "react-dom"
import { cn } from "./cn"
import { MODAL_FIXED_BELOW_NAVBAR_CLASS } from "./DetailModalShell"
import ModalCloseButton from "./ModalCloseButton"
import {
  MODAL_BODY_SCROLL_CLASS,
  MODAL_FOOTER_CLASS,
  MODAL_HEADER_CLASS,
  MODAL_PANEL_MAX_HEIGHT_BELOW_NAV_CLASS,
  MODAL_PANEL_MAX_HEIGHT_CLASS,
  MODAL_PANEL_SHELL_CLASS,
  useModalScrollLock,
} from "./modalLayout"

export type ModalProps = {
  open: boolean
  onClose: () => void
  title?: string
  children: ReactNode
  footer?: ReactNode
  /** Panel width cap */
  size?: "sm" | "md" | "lg"
  /** Anchor overlay below the fixed navbar (top-16), top-aligned on all breakpoints. */
  belowNavbar?: boolean
  /** Disable the top-right close control (e.g. while saving). */
  closeDisabled?: boolean
  className?: string
  panelClassName?: string
  backdropClassName?: string
  bodyClassName?: string
}

const sizeClasses = {
  sm: "max-w-sm",
  md: "max-w-lg",
  lg: "max-w-2xl",
}

export default function Modal({
  open,
  onClose,
  title,
  children,
  footer,
  size = "md",
  belowNavbar = false,
  closeDisabled = false,
  className,
  panelClassName,
  backdropClassName,
  bodyClassName,
}: ModalProps) {
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

  if (!open || !mounted) return null

  return createPortal(
    <div
      className={cn(
        belowNavbar
          ? `${MODAL_FIXED_BELOW_NAVBAR_CLASS} z-[10050] p-4`
          : "fixed inset-0 z-[10050] flex items-start justify-center overflow-y-auto overscroll-contain p-4 sm:items-center",
        className
      )}
      role="presentation"
      onClick={closeDisabled ? undefined : onClose}
    >
      <div
        className={cn(
          "absolute inset-0 bg-black/50 backdrop-blur-sm",
          backdropClassName
        )}
        aria-hidden
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={cn(
          "relative my-auto w-full p-0",
          MODAL_PANEL_SHELL_CLASS,
          belowNavbar
            ? MODAL_PANEL_MAX_HEIGHT_BELOW_NAV_CLASS
            : MODAL_PANEL_MAX_HEIGHT_CLASS,
          sizeClasses[size],
          panelClassName
        )}
        onClick={(e) => e.stopPropagation()}
      >
        <ModalCloseButton
          onClick={onClose}
          disabled={closeDisabled}
          className="absolute right-4 top-4 z-10"
        />
        {title ? (
          <div className={cn(MODAL_HEADER_CLASS, "px-6 py-4 pr-12")}>
            <h2 className="text-lg font-semibold text-white">{title}</h2>
          </div>
        ) : null}
        <div
          className={cn(
            MODAL_BODY_SCROLL_CLASS,
            title ? "px-6 py-4" : "p-6 pt-12",
            bodyClassName
          )}
        >
          {children}
        </div>
        {footer ? (
          <div className={cn(MODAL_FOOTER_CLASS, "px-6 py-4")}>{footer}</div>
        ) : null}
      </div>
    </div>,
    document.body
  )
}
