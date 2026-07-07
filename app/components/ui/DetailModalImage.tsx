"use client"

import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"

type DetailModalImageProps = {
  src: string
  onClick?: (url: string) => void
}

/** Modal screenshot: natural aspect in feed, capped height for very tall images. */
export default function DetailModalImage({ src, onClick }: DetailModalImageProps) {
  return (
    <TradeScreenshotImage
      src={src}
      preset="feed-detail"
      maxHeightPx={720}
      onClick={onClick}
      logContext="detail-modal-screenshot"
      className="md:max-h-full"
    />
  )
}
