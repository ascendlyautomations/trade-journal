"use client"

import { useCallback, useEffect, useState, type ReactNode } from "react"

export const DEFAULT_AVATAR_SRC = "/default-avatar.png"

type SafeProfileAvatarProps = {
  src: string | null | undefined
  alt?: string
  /** Outer box size + layout, e.g. "w-6 h-6" */
  className: string
  fallback: ReactNode
}

export function SafeProfileAvatar({
  src,
  alt = "",
  className,
  fallback,
}: SafeProfileAvatarProps) {
  const [displaySrc, setDisplaySrc] = useState<string | null>(null)

  useEffect(() => {
    const t = typeof src === "string" ? src.trim() : ""
    setDisplaySrc(t.length > 0 ? t : null)
  }, [src])

  const onError = useCallback(() => {
    setDisplaySrc((prev) => {
      if (!prev) return null
      if (prev !== DEFAULT_AVATAR_SRC) return DEFAULT_AVATAR_SRC
      return null
    })
  }, [])

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
        className="h-full w-full object-cover"
        onError={onError}
      />
    </div>
  )
}
