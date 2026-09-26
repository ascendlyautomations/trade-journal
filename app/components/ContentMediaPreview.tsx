"use client"

import type { SyntheticEvent } from "react"
import StorageImage from "@/app/components/ui/StorageImage"
import type { StorageImagePreset } from "@/lib/optimizedStorageImage"
import {
  resolveTradeScreenshotDisplayMode,
  type TradeScreenshotDisplayMode,
} from "@/lib/tradeScreenshotDisplay"
import "./contentMediaPreview.css"

export const CONTENT_MEDIA_PREVIEW_MAX_HEIGHT_PX = 520

type ContentMediaPreviewProps = {
  src: string
  alt?: string
  preset?: StorageImagePreset
  /** Trade Fit shows the whole image. Fill covers the bounded width. */
  displayMode?: TradeScreenshotDisplayMode | string | null
  /**
   * card: scrolling surfaces outside Feed (contain, or Fill when a trade asks).
   * detail: complete image in a modal.
   * feed: complete image, contained inside the Feed's max width and height. Ignores trade Fit/Fill.
   */
  context?: "card" | "detail" | "feed"
  /** @deprecated Prefer `context`. Card ceiling, or a larger in-modal inspection view. */
  variant?: "card" | "detail"
  onClick?: (url: string) => void
  priority?: boolean
  className?: string
  imageClassName?: string
}

/**
 * Scrolling content preview. Aspect comes from the file.
 * Desktop height is capped; the image is not stretched or re-cropped
 * unless the trade's Fit/Fill setting is Fill.
 */
export default function ContentMediaPreview({
  src,
  alt = "",
  preset = "feed-thumb",
  displayMode,
  context,
  variant = "card",
  onClick,
  priority = false,
  className = "",
  imageClassName = "",
}: ContentMediaPreviewProps) {
  const resolvedContext = context ?? (variant === "detail" ? "detail" : "card")
  const mode = resolveTradeScreenshotDisplayMode(displayMode)
  const detailClass = resolvedContext === "detail" ? "tt-content-media-preview--detail" : ""
  const click = onClick
    ? (event: SyntheticEvent) => {
        event.stopPropagation()
        onClick(src)
      }
    : undefined

  if (resolvedContext === "feed") {
    return (
      <div
        className={`tt-content-media-frame tt-content-media-frame--feed flex w-full items-center justify-center bg-black/30 ${className}`}
      >
        <StorageImage
          src={src}
          originalSrc={src}
          preset="feed-card"
          alt={alt}
          priority={priority}
          fallbackToOriginal
          className={`tt-content-media-preview tt-content-media-preview--feed block h-auto w-auto max-w-full object-contain object-center ${
            onClick ? "cursor-pointer" : ""
          } ${imageClassName}`}
          onClick={click}
        />
      </div>
    )
  }

  if (mode === "fill") {
    return (
      <div
        className={`w-full overflow-hidden bg-black/30 ${className}`}
      >
        <StorageImage
          src={src}
          originalSrc={src}
          preset={preset}
          alt={alt}
          priority={priority}
          fallbackToOriginal
          className={`tt-content-media-preview tt-content-media-preview--fill ${detailClass} block h-auto w-full object-cover object-center ${
            onClick ? "cursor-pointer" : ""
          } ${imageClassName}`}
          onClick={click}
        />
      </div>
    )
  }

  return (
    <div
      className={`flex w-full items-center justify-center bg-black/30 ${className}`}
    >
      <StorageImage
        src={src}
        originalSrc={src}
        preset={preset}
        alt={alt}
        priority={priority}
        fallbackToOriginal
        className={`tt-content-media-preview ${detailClass} block h-auto w-auto max-w-full object-contain object-center ${
          onClick ? "cursor-pointer" : ""
        } ${imageClassName}`}
        onClick={click}
      />
    </div>
  )
}
