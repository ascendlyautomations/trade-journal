"use client"

import { useEffect, useState } from "react"
import { createPortal } from "react-dom"
import { NAVBAR_HEIGHT_CLASS } from "./DetailModalShell"

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
  zIndexClass = "z-[9998]",
  belowNavbar = false,
}: ImageLightboxProps) {
  const isOpen = open ?? Boolean(imageUrl)
  const [visible, setVisible] = useState(false)
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!isOpen) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault()
        e.stopPropagation()
        onClose()
      }
    }
    window.addEventListener("keydown", onKey, true)
    return () => window.removeEventListener("keydown", onKey, true)
  }, [isOpen, onClose])

  useEffect(() => {
    if (!isOpen) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [isOpen])

  useEffect(() => {
    if (!isOpen) {
      setVisible(false)
      return
    }
    const frame = requestAnimationFrame(() => setVisible(true))
    return () => cancelAnimationFrame(frame)
  }, [isOpen])

  if (!isOpen || !imageUrl || !mounted) return null

  const overlayClass = belowNavbar
    ? `fixed inset-x-0 bottom-0 ${NAVBAR_HEIGHT_CLASS}`
    : "fixed inset-0"

  const imageMaxHeight = belowNavbar
    ? "max-h-[calc(100dvh-var(--navbar-height,4rem)-2rem)]"
    : "max-h-[95vh]"

  return createPortal(
    <div
      className={`${overlayClass} ${zIndexClass} flex items-start justify-center overflow-y-auto bg-black/75 p-4 pt-3 backdrop-blur-md transition-opacity duration-300 ease-out sm:p-6 sm:pt-4 ${
        visible ? "opacity-100" : "opacity-0"
      }`}
      role="dialog"
      aria-modal="true"
      aria-label="Image viewer"
      onClick={onClose}
    >
      <button
        type="button"
        onClick={onClose}
        className="absolute right-3 top-3 z-10 flex h-10 w-10 items-center justify-center rounded-full bg-black/60 text-2xl leading-none text-white transition hover:bg-black/80 md:right-4 md:top-4"
        aria-label="Close image viewer"
      >
        ×
      </button>

      <img
        src={imageUrl}
        alt={alt}
        decoding="async"
        className={`${imageMaxHeight} w-auto max-w-[min(95vw,100%)] object-contain transition-transform duration-300 ease-out ${
          visible ? "scale-100" : "scale-[0.98]"
        }`}
        style={{ touchAction: "pinch-zoom", imageRendering: "auto" }}
        onClick={(e) => e.stopPropagation()}
      />
    </div>,
    document.body
  )
}
