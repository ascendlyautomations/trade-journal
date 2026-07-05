"use client"

import { useCallback } from "react"

type ReelNativeVideoThumbProps = {
  src: string
  className?: string
  /** Seek once metadata loads to avoid all-black first frames. */
  seekOnLoad?: number
}

export default function ReelNativeVideoThumb({
  src,
  className,
  seekOnLoad = 0.1,
}: ReelNativeVideoThumbProps) {
  const handleLoadedMetadata = useCallback(
    (e: React.SyntheticEvent<HTMLVideoElement>) => {
      const video = e.currentTarget
      if (!Number.isFinite(video.duration) || video.duration <= 0) return
      const target = Math.min(
        seekOnLoad,
        Math.max(video.duration - 0.05, 0)
      )
      if (Math.abs(video.currentTime - target) > 0.01) {
        video.currentTime = target
      }
    },
    [seekOnLoad]
  )

  return (
    <video
      src={src}
      preload="metadata"
      muted
      playsInline
      aria-hidden
      className={className}
      onLoadedMetadata={handleLoadedMetadata}
    />
  )
}
