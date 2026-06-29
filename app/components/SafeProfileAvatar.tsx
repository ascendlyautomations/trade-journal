"use client"

import { useCallback, useEffect, useState, type ReactNode } from "react"
import { isImageUrlLoaded, markImageUrlLoaded } from "@/lib/imageUrlCache"

export function normalizeAvatarSrc(src: string | null | undefined): string | null {
  const t = typeof src === "string" ? src.trim() : ""
  return t.length > 0 ? t : null
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
}: ProfileAvatarImgProps) {
  const [displaySrc, setDisplaySrc] = useState<string | null>(() =>
    normalizeAvatarSrc(src)
  )
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    setDisplaySrc(normalizeAvatarSrc(src))
    setFailed(false)
  }, [src])

  const onError = useCallback(() => {
    setFailed(true)
    setDisplaySrc(null)
  }, [])

  const onLoad = useCallback(() => {
    if (displaySrc) markImageUrlLoaded(displaySrc)
  }, [displaySrc])

  const showImage = Boolean(displaySrc && !failed)
  const fallbackNode = fallback ?? <DefaultAvatarFallback />
  const outerClass = outerAvatarClassName(className)

  if (!showImage) {
    return <div className={outerClass}>{fallbackNode}</div>
  }

  return (
    <div className={outerClass}>
      <img
        src={displaySrc!}
        alt={alt}
        loading={priority || isImageUrlLoaded(displaySrc!) ? "eager" : "lazy"}
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
