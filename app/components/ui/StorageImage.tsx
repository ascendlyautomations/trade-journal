"use client"

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ComponentPropsWithoutRef,
  type SyntheticEvent,
} from "react"
import { isImageUrlLoaded, markImageUrlLoaded } from "@/lib/imageUrlCache"
import {
  normalizeImageSrc,
  optimizeStorageImageUrl,
  type StorageImagePreset,
} from "@/lib/optimizedStorageImage"

type StorageImageProps = Omit<
  ComponentPropsWithoutRef<"img">,
  "src" | "width" | "height"
> & {
  src: string | null | undefined
  preset: StorageImagePreset
  /** Full-resolution URL for lightbox / click handlers (defaults to src). */
  originalSrc?: string | null
  transformWidth?: number
  transformHeight?: number
  /** Optional Next image optimization width for local public assets. */
  localTransformWidth?: number
  priority?: boolean
  intrinsicWidth?: number
  intrinsicHeight?: number
  /** Disable original-byte fallback for bandwidth-sensitive previews. */
  fallbackToOriginal?: boolean
}

/**
 * Lazy-loaded storage image with Supabase transform sizing and original URL fallback.
 */
export default function StorageImage({
  src,
  preset,
  originalSrc,
  transformWidth,
  transformHeight,
  localTransformWidth,
  priority = false,
  intrinsicWidth,
  intrinsicHeight,
  fallbackToOriginal = true,
  alt = "",
  onError,
  onLoad,
  ...rest
}: StorageImageProps) {
  const original = useMemo(
    () => normalizeImageSrc(originalSrc ?? src),
    [originalSrc, src]
  )

  const optimized = useMemo(
    () => {
      const normalized = normalizeImageSrc(src)
      if (
        normalized?.startsWith("/") &&
        !normalized.startsWith("//") &&
        localTransformWidth
      ) {
        return `/_next/image?url=${encodeURIComponent(normalized)}&w=${localTransformWidth}&q=75`
      }

      return optimizeStorageImageUrl(src, preset, {
        width: transformWidth,
        height: transformHeight,
      })
    },
    [src, preset, transformWidth, transformHeight, localTransformWidth]
  )

  const [requestSrc, setRequestSrc] = useState<string | null>(
    () => optimized ?? original
  )
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    setRequestSrc(optimized ?? original)
    setFailed(false)
  }, [optimized, original])

  const handleError = useCallback(
    (event: SyntheticEvent<HTMLImageElement>) => {
      if (fallbackToOriginal && original && requestSrc !== original) {
        setRequestSrc(original)
        return
      }
      setFailed(true)
      onError?.(event)
    },
    [fallbackToOriginal, original, requestSrc, onError]
  )

  const handleLoad = useCallback(
    (event: SyntheticEvent<HTMLImageElement>) => {
      if (requestSrc) markImageUrlLoaded(requestSrc)
      onLoad?.(event)
    },
    [requestSrc, onLoad]
  )

  if (!requestSrc || failed) return null

  return (
    <img
      {...rest}
      src={requestSrc}
      alt={alt}
      width={intrinsicWidth}
      height={intrinsicHeight}
      loading={
        priority || (requestSrc && isImageUrlLoaded(requestSrc))
          ? "eager"
          : "lazy"
      }
      decoding="async"
      fetchPriority={priority ? "high" : undefined}
      onError={handleError}
      onLoad={handleLoad}
    />
  )
}
