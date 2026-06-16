"use client"

import { useEffect } from "react"

type ImageLightboxProps = {
  imageUrl: string | null
  onClose: () => void
  zIndexClass?: string
}

export default function ImageLightbox({
  imageUrl,
  onClose,
  zIndexClass = "z-[9500]",
}: ImageLightboxProps) {
  useEffect(() => {
    if (!imageUrl) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault()
        e.stopPropagation()
        onClose()
      }
    }
    window.addEventListener("keydown", onKey, true)
    return () => window.removeEventListener("keydown", onKey, true)
  }, [imageUrl, onClose])

  if (!imageUrl) return null

  return (
    <div
      className={`fixed inset-0 ${zIndexClass} flex items-center justify-center bg-black/80`}
      role="presentation"
      onClick={onClose}
    >
      <img
        src={imageUrl}
        alt=""
        loading="lazy"
        decoding="async"
        className="max-h-[90%] max-w-[90%] rounded-lg"
        onClick={(e) => e.stopPropagation()}
      />
    </div>
  )
}
