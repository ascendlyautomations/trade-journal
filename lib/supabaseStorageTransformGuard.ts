/**
 * Supabase Storage Image Transformations are disabled for delivery.
 * Upload-time optimized assets + object/public reads only.
 */

import { toSupabaseObjectPublicUrl } from "./storageOptimizedMedia.ts"

export const SUPABASE_STORAGE_RENDER_PUBLIC = "/storage/v1/render/image/public/"

export function isSupabaseStorageTransformUrl(url: string): boolean {
  return url.includes(SUPABASE_STORAGE_RENDER_PUBLIC)
}

/** Throws in tests/dev if a delivery URL would hit Supabase transforms. */
export function assertNoSupabaseStorageTransformUrl(
  url: string,
  context?: string
): void {
  if (!isSupabaseStorageTransformUrl(url)) return
  const suffix = context ? ` (${context})` : ""
  throw new Error(
    `Supabase Storage transform URL is forbidden${suffix}: ${url}`
  )
}

/** Normalize Supabase public URLs to object/public (strip render + query). */
export function supabaseStorageDeliveryUrl(raw: string): string {
  const trimmed = raw.trim()
  if (!trimmed) return trimmed
  if (
    !trimmed.includes("/storage/v1/object/public/") &&
    !trimmed.includes(SUPABASE_STORAGE_RENDER_PUBLIC)
  ) {
    return trimmed
  }
  const objectUrl = toSupabaseObjectPublicUrl(trimmed)
  assertNoSupabaseStorageTransformUrl(objectUrl, "supabaseStorageDeliveryUrl")
  return objectUrl
}
