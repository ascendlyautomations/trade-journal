"use client"

import type { ReactNode } from "react"
import Modal from "@/app/components/ui/Modal"
import { usePlatformPresentation } from "./usePlatformPresentation"
import NativeIosPlatformSheet from "./native/NativeIosPlatformSheet"

export type PlatformSheetProps = {
  open: boolean
  onClose: () => void
  title?: string
  ariaLabel?: string
  children: ReactNode
  /** Web-only size when falling back to Modal. */
  size?: "sm" | "md" | "lg"
  maxHeightClassName?: string
  showCloseButton?: boolean
}

/**
 * Temporary-control presentation (filters, sort, timeframe, pickers).
 * Native iOS: bottom sheet. Web: centered Modal (unchanged card pattern).
 */
export default function PlatformSheet({
  open,
  onClose,
  title,
  ariaLabel,
  children,
  size = "md",
  maxHeightClassName,
  showCloseButton = true,
}: PlatformSheetProps) {
  const { isNativeIos } = usePlatformPresentation()

  if (isNativeIos) {
    return (
      <NativeIosPlatformSheet
        open={open}
        onClose={onClose}
        title={title}
        ariaLabel={ariaLabel}
        maxHeightClassName={maxHeightClassName}
        showCloseButton={showCloseButton}
      >
        {children}
      </NativeIosPlatformSheet>
    )
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title}
      size={size}
      showCloseButton={showCloseButton}
    >
      {children}
    </Modal>
  )
}
