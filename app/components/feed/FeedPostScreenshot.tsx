"use client"

import { memo } from "react"

const VARIANT_CLASSES = {
  thumbnail: "w-full max-h-[400px] object-cover block",
  detail:
    "w-full max-h-[60dvh] object-contain block cursor-pointer bg-black/30",
} as const

type FeedPostScreenshotProps = {
  imageSrc: string | null
  variant?: keyof typeof VARIANT_CLASSES
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

  const resolvedClassName = imgClassName ?? VARIANT_CLASSES[variant]
  const resolvedWrapper =
    wrapperClassName !== undefined
      ? wrapperClassName
      : variant === "detail"
        ? "w-full bg-black/30"
        : "w-full bg-black/30"

  const img = (
    <img
      src={imageSrc}
      alt=""
      loading="lazy"
      decoding="async"
      className={resolvedClassName}
      onClick={
        onImageClick
          ? (e) => {
              e.stopPropagation()
              onImageClick(imageSrc)
            }
          : undefined
      }
    />
  )

  if (!resolvedWrapper) return img

  return <div className={resolvedWrapper}>{img}</div>
}

export default memo(FeedPostScreenshot)
