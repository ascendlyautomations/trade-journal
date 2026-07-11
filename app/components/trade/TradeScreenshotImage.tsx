"use client"

import StorageImage from "@/app/components/ui/StorageImage"
import type { StorageImagePreset } from "@/lib/optimizedStorageImage"

type TradeScreenshotImageProps = {
  src: string
  preset?: StorageImagePreset
  alt?: string
  className?: string
  maxHeightPx?: number
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
  onClick,
}: TradeScreenshotImageProps) {
  const clickHandler = onClick
    ? (event: React.SyntheticEvent) => {
        event.stopPropagation()
        onClick(src)
      }
    : undefined

  return (
    <StorageImage
      src={src}
      originalSrc={src}
      preset={preset}
      alt={alt}
      className={`block h-auto w-full max-w-full object-contain ${onClick ? "cursor-pointer" : ""} ${className}`}
      style={
        maxHeightPx != null
          ? { maxHeight: `min(70dvh, ${maxHeightPx}px)` }
          : undefined
      }
      onClick={clickHandler}
    />
  )
}
