"use client"

import { memo } from "react"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import { TRADE_SCREENSHOT_MAX_HEIGHT_PX } from "@/lib/tradeScreenshotDisplay"

const DETAIL_MAX_HEIGHT_PX = 720

type FeedPostScreenshotProps = {
  imageSrc: string | null
  variant?: "thumbnail" | "detail"
  imgClassName?: string
  wrapperClassName?: string
  onImageClick?: (url: string) => void
}

function FeedPostScreenshot({
  imageSrc,
  variant = "thumbnail",
  imgClassName,
  wrapperClassName,
  onImageClick,
}: FeedPostScreenshotProps) {
  if (!imageSrc) return null

  const image = (
    <TradeScreenshotImage
      src={imageSrc}
      preset={variant === "detail" ? "feed-detail" : "feed-thumb"}
      className={imgClassName}
      maxHeightPx={
        variant === "detail" ? DETAIL_MAX_HEIGHT_PX : TRADE_SCREENSHOT_MAX_HEIGHT_PX
      }
      onClick={onImageClick}
      logContext={`feed-post-screenshot:${variant}`}
    />
  )

  if (wrapperClassName === "") return image
  if (wrapperClassName) return <div className={wrapperClassName}>{image}</div>

  return image
}

export default memo(FeedPostScreenshot)
