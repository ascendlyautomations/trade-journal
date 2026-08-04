"use client"

import { useEffect, useState, type ReactNode } from "react"
import { createPortal } from "react-dom"
import { MODAL_FIXED_BELOW_NAVBAR_CLASS } from "./DetailModalShell"
import ModalCloseButton from "./ModalCloseButton"
import { cn } from "./cn"
import {
  MODAL_BODY_SCROLL_CLASS,
  MODAL_FOOTER_CLASS,
  MODAL_HEADER_CLASS,
  MODAL_OVERLAY_SAFE_PADDING_CLASS,
  MODAL_PANEL_MAX_HEIGHT_BELOW_NAV_CLASS,
  MODAL_PANEL_MAX_HEIGHT_CLASS,
  MODAL_PANEL_SHELL_CLASS,
  useModalScrollLock,
} from "./modalLayout"
import { usePlatformPresentation } from "@/app/components/platform/usePlatformPresentation"
import NativeIosPlatformModal from "@/app/components/platform/native/NativeIosPlatformModal"

export type ScrollableModalShellProps = {
  open: boolean
  onClose: () => void
  ariaLabel: string
  children: ReactNode
  header?: ReactNode
  footer?: ReactNode
  belowNavbar?: boolean
  showCloseButton?: boolean
  closeDisabled?: boolean
  closeButtonClassName?: string
  overlayClassName?: string
  backdropClassName?: string
  panelClassName?: string
  headerClassName?: string
  bodyClassName?: string
  footerClassName?: string
  onOverlayClick?: () => void
}

export default function ScrollableModalShell({
  open,
  onClose,
  ariaLabel,
  children,
  header,
  footer,
  belowNavbar = false,
  showCloseButton = true,
  closeDisabled = false,
  closeButtonClassName = "absolute right-4 top-4 z-10",
  overlayClassName,
  backdropClassName = "bg-black/50 backdrop-blur-sm",
  panelClassName,
  headerClassName,
  bodyClassName,
  footerClassName,
  onOverlayClick,
}: ScrollableModalShellProps) {
  const { isNativeIos } = usePlatformPresentation()
  const [mounted, setMounted] = useState(false)
  useModalScrollLock(open && !isNativeIos)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open || closeDisabled || isNativeIos) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose, closeDisabled, isNativeIos])

  if (isNativeIos) {
    return (
      <NativeIosPlatformModal
        open={open}
        onClose={onClose}
        ariaLabel={ariaLabel}
        header={header}
        footer={footer}
        showCloseButton={showCloseButton}
        closeDisabled={closeDisabled}
        bodyClassName={cn(MODAL_BODY_SCROLL_CLASS, bodyClassName)}
        footerClassName={footerClassName}
        zIndexClass="z-[10050]"
      >
        {children}
      </NativeIosPlatformModal>
    )
  }

  if (!open || !mounted) return null

  const handleOverlayClick = onOverlayClick ?? onClose

  return createPortal(
    <div
      className={cn(
        belowNavbar
          ? `${MODAL_FIXED_BELOW_NAVBAR_CLASS} z-[10050] p-3 pb-[max(0.75rem,var(--safe-area-bottom))] sm:p-4 sm:pb-[max(1rem,var(--safe-area-bottom))]`
          : `fixed inset-0 z-[10050] flex items-start justify-center overflow-y-auto overscroll-contain ${MODAL_OVERLAY_SAFE_PADDING_CLASS} sm:items-center`,
        overlayClassName
      )}
      role="presentation"
      onClick={closeDisabled ? undefined : handleOverlayClick}
    >
      <div
        className={cn("absolute inset-0 z-0", backdropClassName)}
        aria-hidden
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={ariaLabel}
        className={cn(
          "relative z-10 my-auto w-full",
          MODAL_PANEL_SHELL_CLASS,
          belowNavbar
            ? MODAL_PANEL_MAX_HEIGHT_BELOW_NAV_CLASS
            : MODAL_PANEL_MAX_HEIGHT_CLASS,
          panelClassName
        )}
        onClick={(e) => e.stopPropagation()}
      >
        {showCloseButton ? (
          <ModalCloseButton
            onClick={onClose}
            disabled={closeDisabled}
            className={closeButtonClassName}
          />
        ) : null}
        {header ? (
          <div
            className={cn(
              MODAL_HEADER_CLASS,
              showCloseButton && "pr-12",
              headerClassName
            )}
          >
            {header}
          </div>
        ) : null}
        <div className={cn(MODAL_BODY_SCROLL_CLASS, bodyClassName)}>
          {children}
        </div>
        {footer ? (
          <div className={cn(MODAL_FOOTER_CLASS, footerClassName)}>{footer}</div>
        ) : null}
      </div>
    </div>,
    document.body
  )
}
