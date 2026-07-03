"use client"

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react"
import { isImageUrlLoaded, markImageUrlLoaded } from "@/lib/imageUrlCache"
import {
  inferAvatarPixelSize,
  normalizeImageSrc,
  optimizeAvatarUrl,
} from "@/lib/optimizedStorageImage"

export function normalizeAvatarSrc(src: string | null | undefined): string | null {
  return normalizeImageSrc(src)
}

/** Lucide User-style silhouette — neutral default for missing profile photos. */
export function DefaultAvatarIcon({
  className = "h-[52%] w-[52%] text-white/60",
}: {
  className?: string
}) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
      <circle cx="12" cy="7" r="4" />
    </svg>
  )
}

export function DefaultAvatarFallback({ className = "" }: { className?: string }) {
  return (
    <div
      className={`flex h-full w-full items-center justify-center bg-zinc-700/95 ${className}`.trim()}
      aria-hidden
    >
      <DefaultAvatarIcon />
    </div>
  )
}

export type ProfileAvatarImgProps = {
  src: string | null | undefined
  alt?: string
  /** Size, rings, borders — same classes previously applied to `<img>`. */
  className?: string
  fallback?: ReactNode
  priority?: boolean
  /** Override inferred Tailwind size for Supabase transform (2× retina px). */
  displaySizePx?: number
}

function outerAvatarClassName(className: string): string {
  const trimmed = className.trim()
  if (!trimmed) return "relative h-10 w-10 shrink-0 overflow-hidden rounded-full"
  return `relative overflow-hidden rounded-full ${trimmed}`
}

export function SafeProfileAvatar({
  src,
  alt = "",
  className = "",
  fallback,
  priority = false,
  displaySizePx,
}: ProfileAvatarImgProps) {
  const originalSrc = useMemo(() => normalizeAvatarSrc(src), [src])
  const pixelSize = displaySizePx ?? inferAvatarPixelSize(className)
  const optimizedSrc = useMemo(
    () => optimizeAvatarUrl(originalSrc, pixelSize),
    [originalSrc, pixelSize]
  )

  const [requestSrc, setRequestSrc] = useState<string | null>(
    () => optimizedSrc ?? originalSrc
  )
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    setRequestSrc(optimizedSrc ?? originalSrc)
    setFailed(false)
  }, [optimizedSrc, originalSrc])

  const onError = useCallback(() => {
    if (originalSrc && requestSrc !== originalSrc) {
      setRequestSrc(originalSrc)
      return
    }
    setFailed(true)
    setRequestSrc(null)
  }, [originalSrc, requestSrc])

  const onLoad = useCallback(() => {
    if (requestSrc) markImageUrlLoaded(requestSrc)
  }, [requestSrc])

  const showImage = Boolean(requestSrc && !failed)
  const fallbackNode = fallback ?? <DefaultAvatarFallback />
  const outerClass = outerAvatarClassName(className)

  if (!showImage) {
    return <div className={outerClass}>{fallbackNode}</div>
  }

  return (
    <div className={outerClass}>
      <img
        src={requestSrc!}
        alt={alt}
        width={pixelSize}
        height={pixelSize}
        loading={
          priority || isImageUrlLoaded(requestSrc!) ? "eager" : "lazy"
        }
        decoding="async"
        fetchPriority={priority ? "high" : undefined}
        className="h-full w-full object-cover"
        onError={onError}
        onLoad={onLoad}
      />
    </div>
  )
}

/** Drop-in replacement for profile `<img>` avatars. */
export function ProfileAvatarImg(props: ProfileAvatarImgProps) {
  return <SafeProfileAvatar {...props} />
}
