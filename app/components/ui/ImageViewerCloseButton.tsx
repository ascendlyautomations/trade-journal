"use client"

import type { MouseEventHandler } from "react"
import { cn } from "./cn"

/** Circular dismiss control for fullscreen image viewers and lightboxes. */
export const IMAGE_VIEWER_CLOSE_BUTTON_CLASS =
  "z-[100] flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-white/10 bg-black/60 text-xl leading-none text-white backdrop-blur-sm transition hover:bg-black/80 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/40 disabled:cursor-not-allowed disabled:opacity-50"

export const IMAGE_VIEWER_CLOSE_BUTTON_POSITION_CLASS =
  "absolute right-3 top-3 md:right-4 md:top-4"

export type ImageViewerCloseButtonProps = {
  onClick: MouseEventHandler<HTMLButtonElement>
  disabled?: boolean
  className?: string
  positionClassName?: string
  /** Defaults to "Close image viewer". */
  "aria-label"?: string
}

export default function ImageViewerCloseButton({
  onClick,
  disabled = false,
  className,
  positionClassName = IMAGE_VIEWER_CLOSE_BUTTON_POSITION_CLASS,
  "aria-label": ariaLabel = "Close image viewer",
}: ImageViewerCloseButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={cn(
        IMAGE_VIEWER_CLOSE_BUTTON_CLASS,
        positionClassName,
        className
      )}
      aria-label={ariaLabel}
    >
      ✕
    </button>
  )
}
