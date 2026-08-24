"use client"

import StorageImage from "@/app/components/ui/StorageImage"
import { getReelPosterImageUrl } from "@/lib/reelVideo"

export type ReelIdlePosterProps = {
  /** Stored JPEG/WebP poster URL — never a video URL. */
  thumbnailUrl?: string | null
  alt?: string
  className?: string
  imagePreset?: "reel-thumb"
  priority?: boolean
}

/**
 * Non-playing Reel card poster — image thumbnail or static placeholder only.
 * Never mounts video, never references video URLs, never captures poster frames.
 */
export default function ReelIdlePoster({
  thumbnailUrl,
  alt = "",
  className = "h-full w-full object-cover",
  imagePreset = "reel-thumb",
  priority = false,
}: ReelIdlePosterProps) {
  const imagePosterUrl = getReelPosterImageUrl(thumbnailUrl)

  if (imagePosterUrl) {
    return (
      <StorageImage
        src={imagePosterUrl}
        originalSrc={imagePosterUrl}
        preset={imagePreset}
        alt={alt}
        priority={priority}
        localTransformWidth={priority ? 640 : undefined}
        className={className}
      />
    )
  }

  return (
    <div
      aria-hidden
      className={`${className} bg-gradient-to-br from-slate-950 via-slate-900 to-black`}
    />
  )
}
