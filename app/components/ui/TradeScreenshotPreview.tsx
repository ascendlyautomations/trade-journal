"use client"

import ContentMediaPreview from "@/app/components/ContentMediaPreview"
import type { TradeScreenshotDisplayMode } from "@/lib/tradeScreenshotDisplay"

type TradeScreenshotPreviewProps = {
  src: string
  fullSrc: string
  displayMode?: TradeScreenshotDisplayMode | string | null
  className?: string
  alt?: string
  onOpenFull: (fullSrc: string) => void
}

/** Bounded trade screenshot for list cards; opens full-resolution URL on click. */
export default function TradeScreenshotPreview({
  src,
  fullSrc,
  displayMode,
  className = "",
  onOpenFull,
  alt = "",
}: TradeScreenshotPreviewProps) {
  return (
    <ContentMediaPreview
      src={src}
      preset="trade-thumb"
      displayMode={displayMode}
      alt={alt}
      className={`mt-4 ${className}`}
      imageClassName="rounded-lg"
      onClick={() => onOpenFull(fullSrc)}
    />
  )
}
