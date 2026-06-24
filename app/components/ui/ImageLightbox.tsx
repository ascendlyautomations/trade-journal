"use client"

import { useEffect } from "react"

type ImageLightboxProps = {
  imageUrl: string | null
  onClose: () => void
  alt?: string
  open?: boolean
  zIndexClass?: string
}

export default function ImageLightbox({
  imageUrl,
  onClose,
  alt = "",
  open,
  zIndexClass = "z-[9500]",
}: ImageLightboxProps) {
  const isOpen = open ?? Boolean(imageUrl)

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

  if (!isOpen || !imageUrl) return null

  return (
    <div
      className={`fixed inset-0 ${zIndexClass} flex items-center justify-center bg-black/90 p-4`}
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
        className="max-h-[95vh] max-w-[95vw] cursor-zoom-in object-contain"
        style={{ touchAction: "pinch-zoom" }}
        onClick={(e) => e.stopPropagation()}
      />
    </div>
  )
}
