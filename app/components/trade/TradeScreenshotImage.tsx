"use client"

import { useCallback, useState, type SyntheticEvent } from "react"
import StorageImage from "@/app/components/ui/StorageImage"
import { logRenderedImageDimensions } from "@/lib/compressImage"
import type { StorageImagePreset } from "@/lib/optimizedStorageImage"
import {
  resolveTradeScreenshotLayout,
  TRADE_SCREENSHOT_MAX_HEIGHT_PX,
  type TradeScreenshotLayout,
} from "@/lib/tradeScreenshotDisplay"

type TradeScreenshotImageProps = {
  src: string
  preset?: StorageImagePreset
  alt?: string
  className?: string
  maxHeightPx?: number
  onClick?: (url: string) => void
  logContext?: string
}

export default function TradeScreenshotImage({
  src,
  preset = "feed-thumb",
  alt = "",
  className = "",
  maxHeightPx = TRADE_SCREENSHOT_MAX_HEIGHT_PX,
  onClick,
  logContext = "trade-screenshot",
}: TradeScreenshotImageProps) {
  const [layout, setLayout] = useState<TradeScreenshotLayout | null>(null)

  const handleLoad = useCallback(
    (event: SyntheticEvent<HTMLImageElement>) => {
      const image = event.currentTarget
      setLayout(
        resolveTradeScreenshotLayout(image.naturalWidth, image.naturalHeight)
      )
      logRenderedImageDimensions(logContext, image, src)
    },
    [logContext, src]
  )

  const clickHandler = onClick
    ? (event: SyntheticEvent) => {
        event.stopPropagation()
        onClick(src)
      }
    : undefined

  if (layout === "tall-crop") {
    return (
      <div
        className={`w-full overflow-hidden ${className}`}
        style={{ maxHeight: `min(70dvh, ${maxHeightPx}px)` }}
      >
        <StorageImage
          src={src}
          originalSrc={src}
          preset={preset}
          alt={alt}
          className="block w-full object-cover object-center"
          style={{
            height: `min(70dvh, ${maxHeightPx}px)`,
            maxHeight: `min(70dvh, ${maxHeightPx}px)`,
          }}
          onLoad={handleLoad}
          onClick={clickHandler}
        />
      </div>
    )
  }

  return (
    <StorageImage
      src={src}
      originalSrc={src}
      preset={preset}
      alt={alt}
      className={`block w-full h-auto max-w-full ${onClick ? "cursor-pointer" : ""} ${className}`}
      onLoad={handleLoad}
      onClick={clickHandler}
    />
  )
}
