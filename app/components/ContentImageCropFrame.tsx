"use client"

import type { SyntheticEvent } from "react"
import StorageImage from "@/app/components/ui/StorageImage"
import type { SavedContentImageCrop } from "@/lib/contentImageCrop"
import type { StorageImagePreset } from "@/lib/optimizedStorageImage"

type ContentImageCropFrameProps = {
  src: string
  crop: SavedContentImageCrop
  alt?: string
  preset?: StorageImagePreset
  className?: string
  imageClassName?: string
  onClick?: (url: string) => void
  priority?: boolean
}

/**
 * Shows the saved crop inside its presentation frame.
 * Positioning matches the iOS draw rect: the crop rectangle fills the frame.
 */
export default function ContentImageCropFrame({
  src,
  crop,
  alt = "",
  preset = "feed-thumb",
  className = "",
  imageClassName = "",
  onClick,
  priority = false,
}: ContentImageCropFrameProps) {
  const { x, y, width, height } = crop.normalizedCrop
  const click = onClick
    ? (event: SyntheticEvent) => {
        event.stopPropagation()
        onClick(src)
      }
    : undefined

  return (
    <div
      className={`tt-content-image-crop relative overflow-hidden bg-black/30 ${className}`}
      style={{
        aspectRatio: String(crop.presentationAspectRatio),
        ["--tt-crop-aspect" as string]: String(crop.presentationAspectRatio),
      }}
    >
      <StorageImage
        src={src}
        originalSrc={src}
        preset={preset}
        alt={alt}
        priority={priority}
        fallbackToOriginal
        className={`absolute max-w-none ${onClick ? "cursor-pointer" : ""} ${imageClassName}`}
        style={{
          width: `${100 / width}%`,
          height: `${100 / height}%`,
          left: `${(-x / width) * 100}%`,
          top: `${(-y / height) * 100}%`,
        }}
        onClick={click}
      />
    </div>
  )
}
