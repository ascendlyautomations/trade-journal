"use client"

import dynamic from "next/dynamic"
import { useCallback, useEffect, useMemo, useState } from "react"
import { createPortal } from "react-dom"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { NAVBAR_HEIGHT_CLASS } from "./DetailModalShell"
import ImageViewerCloseButton from "./ImageViewerCloseButton"
import SavedImage from "./SavedImage"
import {
  MODAL_PANEL_MAX_HEIGHT_BELOW_NAV_CLASS,
  MODAL_PANEL_MAX_HEIGHT_CLASS,
  MODAL_PANEL_SHELL_CLASS,
  useModalScrollLock,
} from "./modalLayout"
import type { NativeIosMediaItem } from "./NativeIosMediaViewer"

const NativeIosMediaViewer = dynamic(() => import("./NativeIosMediaViewer"), {
  ssr: false,
})

/** Above fixed navbar (z-[9999]) and demo banner; below standard modals (z-[10050]). */
export const IMAGE_LIGHTBOX_Z_INDEX_CLASS = "z-[10001]"

const IMAGE_LIGHTBOX_SAFE_PADDING =
  "p-3 pt-[max(0.75rem,var(--safe-area-top))] pb-[max(0.75rem,var(--safe-area-bottom))] sm:p-4 sm:pt-[max(1rem,var(--safe-area-top))] sm:pb-[max(1rem,var(--safe-area-bottom))]"

type ImageLightboxProps = {
  imageUrl: string | null
  onClose: () => void
  alt?: string
  open?: boolean
  zIndexClass?: string
  /** Anchor below the fixed navbar instead of covering the full viewport. */
  belowNavbar?: boolean
  /**
   * Optional gallery. On Capacitor iOS, enables horizontal paging.
   * Desktop / mobile web still show `imageUrl` only (unchanged).
   */
  images?: string[]
  /** Index within `images` when opening a gallery (native iOS only). */
  initialIndex?: number
}

export default function ImageLightbox({
  imageUrl,
  onClose,
  alt = "",
  open,
  zIndexClass = IMAGE_LIGHTBOX_Z_INDEX_CLASS,
  belowNavbar = false,
  images,
  initialIndex = 0,
}: ImageLightboxProps) {
  const nativeIos = useIsNativeIos()
  const isOpen = open ?? Boolean(imageUrl)
  const [visible, setVisible] = useState(false)
  const [mounted, setMounted] = useState(false)
  const showViewer = isOpen && Boolean(imageUrl) && mounted

  const nativeItems = useMemo((): NativeIosMediaItem[] => {
    const urls =
      images && images.length > 0
        ? images.filter((url) => Boolean(url?.trim()))
        : imageUrl
          ? [imageUrl]
          : []
    return urls.map((url) => ({ type: "image" as const, url, alt }))
  }, [alt, imageUrl, images])

  const nativeStartIndex = useMemo(() => {
    if (!imageUrl || nativeItems.length === 0) return 0
    const fromProp = images?.length
      ? Math.max(0, Math.min(initialIndex, nativeItems.length - 1))
      : 0
    const match = nativeItems.findIndex((item) => item.url === imageUrl)
    return match >= 0 ? match : fromProp
  }, [imageUrl, images, initialIndex, nativeItems])

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!showViewer || nativeIos) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault()
        e.stopPropagation()
        onClose()
      }
    }
    window.addEventListener("keydown", onKey, true)
    return () => window.removeEventListener("keydown", onKey, true)
  }, [showViewer, onClose, nativeIos])

  useModalScrollLock(showViewer && !nativeIos)

  useEffect(() => {
    if (!showViewer || nativeIos) {
      setVisible(false)
      return
    }
    const frame = requestAnimationFrame(() => setVisible(true))
    return () => cancelAnimationFrame(frame)
  }, [showViewer, nativeIos])

  const stopPropagation = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
  }, [])

  if (!showViewer) return null

  // Capacitor iOS: Photos-style viewer. Web / Android keep the existing lightbox.
  if (nativeIos) {
    return (
      <NativeIosMediaViewer
        open
        items={nativeItems}
        initialIndex={nativeStartIndex}
        onClose={onClose}
        zIndexClass={zIndexClass}
      />
    )
  }

  const overlayClass = belowNavbar
    ? `fixed inset-x-0 bottom-0 ${NAVBAR_HEIGHT_CLASS}`
    : "fixed inset-0"

  const panelMaxHeightClass = belowNavbar
    ? MODAL_PANEL_MAX_HEIGHT_BELOW_NAV_CLASS
    : MODAL_PANEL_MAX_HEIGHT_CLASS

  const imageMaxHeight = belowNavbar
    ? "max-h-[min(75dvh,calc(100dvh-var(--app-header-offset)-var(--safe-area-bottom)-7rem))]"
    : "max-h-[min(75dvh,calc(100dvh-var(--safe-area-top)-var(--safe-area-bottom)-7rem))]"

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
