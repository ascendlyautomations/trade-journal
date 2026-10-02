/**
 * Supabase Storage delivery — object/public URLs only (no Image Transformations).
 *
 * Upload-time optimized assets (`/opt/` in the storage path) and legacy objects
 * are both fetched via `/storage/v1/object/public/…`.
 */

import {
  debugLogStorageImageDelivery,
  isOptimizedStorageObjectPath,
  toSupabaseObjectPublicUrl,
} from "./storageOptimizedMedia.ts"
import {
  assertNoSupabaseStorageTransformUrl,
  supabaseStorageDeliveryUrl,
  SUPABASE_STORAGE_RENDER_PUBLIC,
} from "./supabaseStorageTransformGuard.ts"

const STORAGE_OBJECT_PUBLIC = "/storage/v1/object/public/"

export type StorageImagePreset =
  | "avatar"
  | "feed-thumb"
  | "feed-card"
  | "feed-detail"
  | "story"
  | "reel-thumb"
  | "achievement"
  | "achievement-card"
  | "trade-thumb"
  | "message-preview"
  | "message-thumb"
  | "message-story-thumb"
  | "room-thumb"
  | "room-list-thumb"

type TransformOptions = {
  width?: number
  height?: number
  quality?: number
  resize?: "cover" | "contain" | "fill"
}

export function isSupabaseStoragePublicUrl(url: string): boolean {
  return (
    url.includes(STORAGE_OBJECT_PUBLIC) ||
    url.includes(SUPABASE_STORAGE_RENDER_PUBLIC)
  )
}

/**
 * @deprecated Supabase Storage transforms are disabled. Returns object/public URL.
 */
export function toSupabaseRenderUrl(
  url: string,
  _options: TransformOptions = {}
): string {
  return supabaseStorageDeliveryUrl(url)
}

/** Infer 2× retina pixel size from Tailwind h-/w- utility (e.g. h-10 → 80px). */
export function inferAvatarPixelSize(className: string, fallback = 80): number {
  const match = className.match(/\b(?:h|w)-(\d+(?:\.\d+)?)\b/)
  if (!match) return fallback
  const unit = parseFloat(match[1]!)
  const displayPx = unit * 4
  return Math.min(256, Math.max(32, Math.round(displayPx * 2)))
}

export function optimizeStorageImageUrl(
  src: string | null | undefined,
  preset: StorageImagePreset,
  _overrides?: Pick<TransformOptions, "width" | "height">
): string | null {
  const raw = src != null ? String(src).trim() : ""
  if (!raw) return null

  if (raw.startsWith("/") && !raw.startsWith("//")) return raw
  if (raw.startsWith("http") && !isSupabaseStoragePublicUrl(raw)) return raw

  const resolved =
    raw.startsWith("http") || isSupabaseStoragePublicUrl(raw) ? raw : null

  if (!resolved) return raw

  if (!isSupabaseStoragePublicUrl(resolved)) return resolved

  const objectUrl = supabaseStorageDeliveryUrl(resolved)
  const assetPolicy = isOptimizedStorageObjectPath(resolved)
    ? "optimizedObject"
    : "legacy"
  debugLogStorageImageDelivery(objectUrl, assetPolicy, "object", preset)
  assertNoSupabaseStorageTransformUrl(objectUrl, `preset=${preset}`)
  return objectUrl
}

export function optimizeAvatarUrl(
  src: string | null | undefined,
  _displaySizePx?: number
): string | null {
  const raw = normalizeImageSrc(src)
  if (!raw) return null
  if (!isSupabaseStoragePublicUrl(raw)) return raw
  const objectUrl = supabaseStorageDeliveryUrl(raw)
  debugLogStorageImageDelivery(objectUrl, "optimizedObject", "object", "avatar")
  assertNoSupabaseStorageTransformUrl(objectUrl, "avatar")
  return objectUrl
}

export function normalizeImageSrc(src: string | null | undefined): string | null {
  const t = typeof src === "string" ? src.trim() : ""
  return t.length > 0 ? t : null
}
