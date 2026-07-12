"use client"

import StorageImage from "@/app/components/ui/StorageImage"
import type { StorageImagePreset } from "@/lib/optimizedStorageImage"

type TradeScreenshotImageProps = {
  src: string
  preset?: StorageImagePreset
  alt?: string
  className?: string
  maxHeightPx?: number
  /** `cover` crops to fill; `contain` (default) shows the full saved image. */
  objectFit?: "contain" | "cover"
  /** With `contain`, size to the parent frame (letterbox; no second crop). */
  fillFrame?: boolean
  onClick?: (url: string) => void
  logContext?: string
}

/**
 * Feed/detail screenshot helper (storage transforms for performance).
 * Trades page + full-screen viewer use {@link SavedImage} for identical composition.
 */
export default function TradeScreenshotImage({
  src,
  preset = "feed-thumb",
  alt = "",
  className = "",
  maxHeightPx,
  objectFit = "contain",
  fillFrame = false,
  onClick,
}: TradeScreenshotImageProps) {
  const clickHandler = onClick
    ? (event: React.SyntheticEvent) => {
        event.stopPropagation()
        onClick(src)
      }
    : undefined

  const sizingClass =
    objectFit === "cover"
      ? "block h-full w-full object-cover object-center"
      : fillFrame
        ? "block object-contain object-center"
        : "block h-auto w-full max-w-full object-contain"

  return (
    <StorageImage
      src={src}
      originalSrc={src}
      preset={preset}
      alt={alt}
      className={`${sizingClass} ${onClick ? "cursor-pointer" : ""} ${className}`}
      style={
        objectFit === "contain" && !fillFrame && maxHeightPx != null
          ? { maxHeight: `min(70dvh, ${maxHeightPx}px)` }
          : undefined
      }
      onClick={clickHandler}
    />
  )
}
