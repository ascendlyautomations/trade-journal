"use client"

import type { CSSProperties, MouseEvent, SyntheticEvent } from "react"

export const SAVED_IMAGE_FIT_CLASS = "w-auto max-w-full object-contain"

type SavedImageProps = {
  src: string
  alt?: string
  /** Sizing only (e.g. max-h-*). Never changes crop/composition. */
  maxHeightClassName: string
  className?: string
  style?: CSSProperties
  onClick?: (event: MouseEvent<HTMLImageElement>) => void
  onLoad?: (event: SyntheticEvent<HTMLImageElement>) => void
  decoding?: "async" | "auto" | "sync"
  draggable?: boolean
}

/**
 * Canonical renderer for a saved image file (trade screenshots, etc.).
 * Same composition rules as the full-screen image viewer:
 * natural aspect ratio, object-contain, no crop/zoom/stretch.
 * Callers may only change displayed size via maxHeightClassName / className.
 */
export default function SavedImage({
  src,
  alt = "",
  maxHeightClassName,
  className = "",
  style,
  onClick,
  onLoad,
  decoding = "async",
  draggable,
}: SavedImageProps) {
  return (
    // eslint-disable-next-line @next/next/no-img-element -- intentional: exact file bytes, no transform pipeline
    <img
      src={src}
      alt={alt}
      decoding={decoding}
      draggable={draggable}
      className={`${maxHeightClassName} ${SAVED_IMAGE_FIT_CLASS} ${
        onClick ? "cursor-pointer" : ""
      } ${className}`}
      style={{ imageRendering: "auto", ...style }}
      onClick={onClick}
      onLoad={onLoad}
    />
  )
}
