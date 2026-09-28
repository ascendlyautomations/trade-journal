/**
 * Phase 1: upload-time optimized assets live under an `/opt/` path segment.
 * Delivery uses object/public URLs (no Supabase Image Transformations).
 */

export const OPTIMIZED_STORAGE_PATH_SEGMENT = "/opt/"

/** Storage object path for a new upload-time optimized JPEG (or other ext). */
export function optimizedStorageObjectPath(
  prefix: string,
  extension = "jpg"
): string {
  const cleanPrefix = prefix.replace(/\/+$/, "")
  const ext = extension.replace(/^\./, "") || "jpg"
  return `${cleanPrefix}/opt/${Date.now()}.${ext}`
}

/** Path segment from a public object or render URL (no query). */
export function storagePublicPathFromUrl(url: string): string | null {
  const trimmed = url.trim()
  if (!trimmed) return null
  const objectMarker = "/storage/v1/object/public/"
  const renderMarker = "/storage/v1/render/image/public/"
  const withoutQuery = trimmed.split("?")[0] ?? trimmed
  const objectIdx = withoutQuery.indexOf(objectMarker)
  if (objectIdx >= 0) {
    return withoutQuery.slice(objectIdx + objectMarker.length)
  }
  const renderIdx = withoutQuery.indexOf(renderMarker)
  if (renderIdx >= 0) {
    return withoutQuery.slice(renderIdx + renderMarker.length)
  }
  return null
}

export function isOptimizedStorageObjectPath(pathOrUrl: string): boolean {
  const path = storagePublicPathFromUrl(pathOrUrl) ?? pathOrUrl
  return path.includes(OPTIMIZED_STORAGE_PATH_SEGMENT)
}

export type StorageImageAssetPolicy = "optimizedObject" | "legacy"
export type StorageImageDelivery = "object" | "transform"

const STORAGE_OBJECT_PUBLIC = "/storage/v1/object/public/"
const STORAGE_RENDER_PUBLIC = "/storage/v1/render/image/public/"

/** Normalize Supabase render URLs back to object/public (strip query). */
export function toSupabaseObjectPublicUrl(url: string): string {
  if (!url.includes(STORAGE_RENDER_PUBLIC) && !url.includes(STORAGE_OBJECT_PUBLIC)) {
    return url.split("?")[0] ?? url
  }
  const base = url.split("?")[0] ?? url
  if (base.includes(STORAGE_RENDER_PUBLIC)) {
    return base.replace(STORAGE_RENDER_PUBLIC, STORAGE_OBJECT_PUBLIC)
  }
  return base
}

export function storageDeliveryIdentity(url: string): string {
  const path = storagePublicPathFromUrl(url)
  if (!path) return "external"
  const parts = path.split("/")
  return parts.slice(-3).join("/") || path
}

export function debugLogStorageImageDelivery(
  url: string,
  assetPolicy: StorageImageAssetPolicy,
  delivery: StorageImageDelivery,
  preset?: string
): void {
  if (process.env.NODE_ENV === "production") return
  const identity = storageDeliveryIdentity(url)
  const presetSuffix = preset ? ` preset=${preset}` : ""
  console.debug(
    `[StorageImageDelivery] assetPolicy=${assetPolicy} delivery=${delivery}${presetSuffix} id=${identity}`
  )
}
