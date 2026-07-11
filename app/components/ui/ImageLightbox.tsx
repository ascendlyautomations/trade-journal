"use client"

import { useCallback, useEffect, useState } from "react"
import { createPortal } from "react-dom"
import { NAVBAR_HEIGHT_CLASS } from "./DetailModalShell"
import ImageViewerCloseButton from "./ImageViewerCloseButton"
import SavedImage from "./SavedImage"
import {
  MODAL_PANEL_MAX_HEIGHT_BELOW_NAV_CLASS,
  MODAL_PANEL_MAX_HEIGHT_CLASS,
  MODAL_PANEL_SHELL_CLASS,
  useModalScrollLock,
} from "./modalLayout"

/** Above fixed navbar (z-[9999]) and demo banner; below standard modals (z-[10050]). */
export const IMAGE_LIGHTBOX_Z_INDEX_CLASS = "z-[10001]"

const IMAGE_LIGHTBOX_SAFE_PADDING =
  "p-3 pt-[max(0.75rem,env(safe-area-inset-top))] pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:p-4 sm:pt-[max(1rem,env(safe-area-inset-top))] sm:pb-[max(1rem,env(safe-area-inset-bottom))]"

type ImageLightboxProps = {
  imageUrl: string | null
  onClose: () => void
  alt?: string
  open?: boolean
  zIndexClass?: string
  /** Anchor below the fixed navbar instead of covering the full viewport. */
  belowNavbar?: boolean
}

export default function ImageLightbox({
  imageUrl,
  onClose,
  alt = "",
  open,
  zIndexClass = IMAGE_LIGHTBOX_Z_INDEX_CLASS,
  belowNavbar = false,
}: ImageLightboxProps) {
  const isOpen = open ?? Boolean(imageUrl)
  const [visible, setVisible] = useState(false)
  const [mounted, setMounted] = useState(false)
  const showViewer = isOpen && Boolean(imageUrl) && mounted

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!showViewer) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault()
        e.stopPropagation()
        onClose()
      }
    }
    window.addEventListener("keydown", onKey, true)
    return () => window.removeEventListener("keydown", onKey, true)
  }, [showViewer, onClose])

  useModalScrollLock(showViewer)

  useEffect(() => {
    if (!showViewer) {
      setVisible(false)
      return
    }
    const frame = requestAnimationFrame(() => setVisible(true))
    return () => cancelAnimationFrame(frame)
  }, [showViewer])

  const stopPropagation = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
  }, [])

  if (!showViewer) return null

  const overlayClass = belowNavbar
    ? `fixed inset-x-0 bottom-0 ${NAVBAR_HEIGHT_CLASS}`
    : "fixed inset-0"

  const panelMaxHeightClass = belowNavbar
    ? MODAL_PANEL_MAX_HEIGHT_BELOW_NAV_CLASS
    : MODAL_PANEL_MAX_HEIGHT_CLASS

  const imageMaxHeight = belowNavbar
    ? "max-h-[min(75dvh,calc(100dvh-var(--navbar-height,4rem)-env(safe-area-inset-top)-env(safe-area-inset-bottom)-7rem))]"
    : "max-h-[min(75dvh,calc(100dvh-env(safe-area-inset-top)-env(safe-area-inset-bottom)-7rem))]"

  return createPortal(
    <div
      className={`${overlayClass} ${zIndexClass} flex items-center justify-center overflow-y-auto overflow-x-hidden bg-black/75 backdrop-blur-md transition-opacity duration-300 ease-out motion-reduce:transition-none ${IMAGE_LIGHTBOX_SAFE_PADDING} ${
        visible ? "opacity-100" : "opacity-0"
      }`}
      role="presentation"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Image viewer"
        className={`relative mx-auto flex w-full max-w-5xl flex-col overflow-hidden ${MODAL_PANEL_SHELL_CLASS} ${panelMaxHeightClass} transition-transform duration-300 ease-out motion-reduce:transition-none ${
          visible ? "scale-100" : "scale-[0.98]"
        }`}
        onClick={stopPropagation}
      >
        <ImageViewerCloseButton
          positionClassName="absolute right-3 top-3 md:right-4 md:top-4"
          className="h-11 w-11 text-2xl md:h-10 md:w-10 md:text-xl"
          onClick={(event) => {
            event.stopPropagation()
            onClose()
          }}
        />

        <div className="flex min-h-0 flex-1 items-center justify-center overflow-hidden px-3 pb-3 pt-14 sm:px-4 sm:pb-4 sm:pt-16 md:px-6 md:pb-6 md:pt-[4.25rem]">
          <SavedImage
            src={imageUrl!}
            alt={alt}
            maxHeightClassName={imageMaxHeight}
            style={{ touchAction: "pinch-zoom" }}
          />
        </div>
      </div>
    </div>,
    document.body
  )
}
