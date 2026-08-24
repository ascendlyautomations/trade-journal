"use client"

import type { ComponentPropsWithoutRef } from "react"
import StorageImage from "@/app/components/ui/StorageImage"
import { SAVED_IMAGE_FIT_CLASS } from "@/app/components/ui/SavedImage"
import { TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS } from "@/lib/tradeScreenshotDisplay"

type TradeScreenshotPreviewProps = Omit<
  ComponentPropsWithoutRef<"img">,
  "src" | "width" | "height"
> & {
  src: string
  fullSrc: string
  maxHeightClassName?: string
  onOpenFull: (fullSrc: string) => void
}

/** Bounded trade screenshot for list cards; opens full-resolution URL on click. */
export default function TradeScreenshotPreview({
  src,
  fullSrc,
  maxHeightClassName = TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS,
  className = "",
  onOpenFull,
  alt = "",
  ...rest
}: TradeScreenshotPreviewProps) {
  return (
    <StorageImage
      src={src}
      originalSrc={fullSrc}
      preset="trade-thumb"
      transformWidth={640}
      alt={alt}
      fallbackToOriginal={false}
      className={`${maxHeightClassName} ${SAVED_IMAGE_FIT_CLASS} mx-auto mt-4 block cursor-pointer rounded-lg ${className}`}
      onClick={() => onOpenFull(fullSrc)}
      {...rest}
    />
  )
}
