"use client"

import { memo } from "react"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import {
  TRADE_IMAGE_ASPECT,
  TRADE_IMAGE_MEDIA_FRAME_IMG_CLASS,
} from "@/lib/tradeImageAspect"
import { TRADE_SCREENSHOT_MAX_HEIGHT_PX } from "@/lib/tradeScreenshotDisplay"

const DETAIL_MAX_HEIGHT_PX = 720

type FeedPostScreenshotProps = {
  imageSrc: string | null
  variant?: "thumbnail" | "detail" | "message"
  /**
   * When set, media sits in a shared aspect-ratio frame (homepage featured cards).
   * Image is contained — no second crop of the saved upload.
   */
  fixedFrameClassName?: string
  imgClassName?: string
  wrapperClassName?: string
  onImageClick?: (url: string) => void
  priority?: boolean
}

function FeedPostScreenshot({
  imageSrc,
  variant = "thumbnail",
  fixedFrameClassName,
  imgClassName,
  wrapperClassName,
  onImageClick,
  priority = false,
}: FeedPostScreenshotProps) {
  const preset =
    variant === "detail"
      ? "feed-detail"
      : variant === "message"
        ? "message-preview"
        : "feed-thumb"

  if (fixedFrameClassName) {
    return (
      <div
        className={fixedFrameClassName}
        style={{ aspectRatio: TRADE_IMAGE_ASPECT }}
      >
        {imageSrc ? (
          <TradeScreenshotImage
            src={imageSrc}
            preset={preset}
            fallbackToOriginal={variant !== "message"}
            objectFit="contain"
            fillFrame
            priority={priority}
            className={imgClassName ?? TRADE_IMAGE_MEDIA_FRAME_IMG_CLASS}
            onClick={onImageClick}
            logContext={`feed-post-screenshot:${variant}:framed`}
          />
        ) : null}
      </div>
    )
  }

  if (!imageSrc) return null

  const image = (
    <TradeScreenshotImage
      src={imageSrc}
      preset={preset}
      fallbackToOriginal={variant !== "message"}
      className={imgClassName}
      maxHeightPx={
        variant === "detail" || variant === "message"
          ? DETAIL_MAX_HEIGHT_PX
          : TRADE_SCREENSHOT_MAX_HEIGHT_PX
      }
      priority={priority}
      onClick={onImageClick}
      logContext={`feed-post-screenshot:${variant}`}
    />
  )

  if (wrapperClassName === "") return image
  if (wrapperClassName) return <div className={wrapperClassName}>{image}</div>

  return image
}

export default memo(FeedPostScreenshot)
