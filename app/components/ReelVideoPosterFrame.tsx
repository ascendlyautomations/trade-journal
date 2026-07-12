"use client"

import { useCallback, useEffect, useState } from "react"
import StorageImage from "@/app/components/ui/StorageImage"
import {
  captureReelPosterFromUrl,
  firstVisibleReelSeekTime,
  getReelPosterImageUrl,
  getReelVideoFrameSource,
} from "@/lib/reelVideo"
import { getCachedReelPosterObjectUrl } from "@/lib/reelPosterCache"

type ReelVideoPosterFrameProps = {
  thumbnailUrl?: string | null
  videoUrl?: string | null
  alt?: string
  className?: string
  imagePreset?: "reel-thumb"
}

function PrimedVideoPoster({
  src,
  className,
}: {
  src: string
  className?: string
}) {
  const primeFrame = useCallback((video: HTMLVideoElement) => {
    if (!Number.isFinite(video.duration) || video.duration <= 0) return
    const target = firstVisibleReelSeekTime(video.duration)
    if (Math.abs(video.currentTime - target) > 0.01) {
      video.currentTime = target
    }
  }, [])

  const handleLoadedData = useCallback(
    (event: React.SyntheticEvent<HTMLVideoElement>) => {
      primeFrame(event.currentTarget)
    },
    [primeFrame]
  )

  return (
    <video
      src={src}
      preload="auto"
      muted
      playsInline
      aria-hidden
      className={className}
      onLoadedData={handleLoadedData}
      onLoadedMetadata={handleLoadedData}
    />
  )
}

export default function ReelVideoPosterFrame({
  thumbnailUrl,
  videoUrl,
  alt = "",
  className = "h-full w-full object-cover",
  imagePreset = "reel-thumb",
}: ReelVideoPosterFrameProps) {
  const imagePosterUrl = getReelPosterImageUrl(thumbnailUrl)
  const frameVideoUrl = imagePosterUrl
    ? null
    : getReelVideoFrameSource(thumbnailUrl, videoUrl)

  const [capturedPosterUrl, setCapturedPosterUrl] = useState<string | null>(
    () => (frameVideoUrl ? getCachedReelPosterObjectUrl(frameVideoUrl) : null)
  )

  useEffect(() => {
    if (imagePosterUrl || !frameVideoUrl || capturedPosterUrl) return

    let cancelled = false

    void captureReelPosterFromUrl(frameVideoUrl)
      .then((url) => {
        if (!cancelled) setCapturedPosterUrl(url)
      })
      .catch(() => {
        // Keep showing the primed video frame fallback.
      })

    return () => {
      cancelled = true
    }
  }, [capturedPosterUrl, frameVideoUrl, imagePosterUrl])

  if (imagePosterUrl) {
    return (
      <StorageImage
        src={imagePosterUrl}
        originalSrc={imagePosterUrl}
        preset={imagePreset}
        alt={alt}
        className={className}
      />
    )
  }

  if (capturedPosterUrl) {
    return (
      <img
        src={capturedPosterUrl}
        alt={alt}
        draggable={false}
        className={className}
      />
    )
  }

  if (frameVideoUrl) {
    return <PrimedVideoPoster src={frameVideoUrl} className={className} />
  }

  return null
}
