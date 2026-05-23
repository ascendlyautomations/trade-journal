"use client"

import { memo } from "react"

type FeedPostScreenshotProps = {
  imageSrc: string | null
  imgClassName?: string
  wrapperClassName?: string
}

function FeedPostScreenshot({
  imageSrc,
  imgClassName = "w-full max-h-[400px] object-cover block",
  wrapperClassName = "w-full bg-black/30",
}: FeedPostScreenshotProps) {
  if (!imageSrc) return null

  const img = (
    <img
      src={imageSrc}
      alt=""
      loading="lazy"
      decoding="async"
      className={imgClassName}
    />
  )

  if (!wrapperClassName) return img

  return <div className={wrapperClassName}>{img}</div>
}

export default memo(FeedPostScreenshot)
