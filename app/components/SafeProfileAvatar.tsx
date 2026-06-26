"use client"

import { useCallback, useEffect, useState, type ReactNode } from "react"
import { isImageUrlLoaded, markImageUrlLoaded } from "@/lib/imageUrlCache"

export const DEFAULT_AVATAR_SRC = "/default-avatar.png"

type SafeProfileAvatarProps = {
  src: string | null | undefined
  alt?: string
  /** Outer box size + layout, e.g. "w-6 h-6" */
  className: string
  fallback: ReactNode
  /** Eager load for above-the-fold avatars (nav, story bar). */
  priority?: boolean
}

export function SafeProfileAvatar({
  src,
  alt = "",
  className,
  fallback,
  priority = false,
}: SafeProfileAvatarProps) {
  const [displaySrc, setDisplaySrc] = useState<string | null>(null)

  useEffect(() => {
    const t = typeof src === "string" ? src.trim() : ""
    if (t.length > 0) {
      setDisplaySrc(t)
      return
    }
    setDisplaySrc(null)
  }, [src])

  const onError = useCallback(() => {
    setDisplaySrc((prev) => {
      if (!prev) return null
      if (prev !== DEFAULT_AVATAR_SRC) return DEFAULT_AVATAR_SRC
      return null
    })
  }, [])

  const onLoad = useCallback(() => {
    if (displaySrc) markImageUrlLoaded(displaySrc)
  }, [displaySrc])

  if (!displaySrc) {
    return (
      <div
        className={`${className} flex shrink-0 items-center justify-center overflow-hidden rounded-full`}
      >
        {fallback}
      </div>
    )
  }

  return (
    <div
      className={`${className} shrink-0 overflow-hidden rounded-full bg-gray-600`}
    >
      <img
        src={displaySrc}
        alt={alt}
        loading={priority || isImageUrlLoaded(displaySrc) ? "eager" : "lazy"}
        decoding="async"
        fetchPriority={priority ? "high" : undefined}
        className="h-full w-full object-cover"
        onError={onError}
        onLoad={onLoad}
      />
    </div>
  )
}
