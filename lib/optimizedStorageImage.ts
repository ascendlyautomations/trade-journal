/**
 * Supabase Storage image transforms — serve appropriately sized images
 * via /storage/v1/render/image/public/ (falls back to original URL on error).
 */

const STORAGE_OBJECT_PUBLIC = "/storage/v1/object/public/"
const STORAGE_RENDER_PUBLIC = "/storage/v1/render/image/public/"

export type StorageImagePreset =
  | "avatar"
  | "feed-thumb"
  | "feed-detail"
  | "story"
  | "reel-thumb"
  | "achievement"
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

const PRESET_TRANSFORMS: Record<
  StorageImagePreset,
  Required<Pick<TransformOptions, "quality">> &
    Pick<TransformOptions, "width" | "height" | "resize">
> = {
  avatar: { width: 96, height: 96, quality: 80, resize: "cover" },
  /** Shared Feed + Profile trade-card screenshot transform (640px @ q75). */
  "feed-thumb": { width: 640, quality: 75 },
  "feed-detail": { width: 1280, quality: 82 },
  story: { width: 1080, quality: 80, resize: "contain" },
  "reel-thumb": { width: 560, height: 996, quality: 75, resize: "cover" },
  achievement: { width: 800, quality: 75 },
  "trade-thumb": { width: 800, quality: 75 },
  "message-preview": { width: 720, quality: 72, resize: "contain" },
  "message-thumb": { width: 320, height: 320, quality: 70, resize: "cover" },
  "message-story-thumb": {
    width: 96,
    height: 96,
    quality: 68,
    resize: "cover",
  },
  /** Trade Room header avatar — 96px @ q80 cover (2× for h-12). */
  "room-thumb": { width: 96, height: 96, quality: 80, resize: "cover" },
  /** Trade Room sidebar list avatar — 64px @ q80 cover (2× for h-8). */
  "room-list-thumb": { width: 64, height: 64, quality: 80, resize: "cover" },
}

export function isSupabaseStoragePublicUrl(url: string): boolean {
  return (
    url.includes(STORAGE_OBJECT_PUBLIC) || url.includes(STORAGE_RENDER_PUBLIC)
  )
}

/** Convert a Supabase public object URL to a render/transform URL. */
export function toSupabaseRenderUrl(
  url: string,
  options: TransformOptions
): string {
  if (!isSupabaseStoragePublicUrl(url)) return url

  const renderBase = url.includes(STORAGE_RENDER_PUBLIC)
    ? url.split("?")[0]!
    : url.replace(STORAGE_OBJECT_PUBLIC, STORAGE_RENDER_PUBLIC).split("?")[0]!

  const params = new URLSearchParams()
  if (options.width != null) params.set("width", String(options.width))
  if (options.height != null) params.set("height", String(options.height))
  if (options.quality != null) params.set("quality", String(options.quality))
  if (options.resize) params.set("resize", options.resize)

  const query = params.toString()
  return query ? `${renderBase}?${query}` : renderBase
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
  overrides?: Pick<TransformOptions, "width" | "height">
): string | null {
  const raw = src != null ? String(src).trim() : ""
  if (!raw) return null

  if (raw.startsWith("/") && !raw.startsWith("//")) return raw
  if (raw.startsWith("http") && !isSupabaseStoragePublicUrl(raw)) return raw

  const base = PRESET_TRANSFORMS[preset]
  const width = overrides?.width ?? base.width
  const height = overrides?.height ?? base.height

  const resolved =
    raw.startsWith("http") || isSupabaseStoragePublicUrl(raw) ? raw : null

  if (!resolved) return raw

  if (!isSupabaseStoragePublicUrl(resolved)) return resolved

  return toSupabaseRenderUrl(resolved, {
    width,
    height,
    quality: base.quality,
    ...(base.resize ? { resize: base.resize } : {}),
  })
}

export function optimizeAvatarUrl(
  src: string | null | undefined,
  displaySizePx?: number
): string | null {
  const raw = normalizeImageSrc(src)
  if (!raw) return null
  if (!isSupabaseStoragePublicUrl(raw)) return raw

  const pixelSize = displaySizePx ?? 80
  return optimizeStorageImageUrl(raw, "avatar", {
    width: pixelSize,
    height: pixelSize,
  })
}

export function normalizeImageSrc(src: string | null | undefined): string | null {
  const t = typeof src === "string" ? src.trim() : ""
  return t.length > 0 ? t : null
}
