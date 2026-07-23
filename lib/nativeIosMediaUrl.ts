/**
 * Prefer full-resolution object URLs inside the native iOS media viewer.
 * Thumbnail/transform URLs remain for adjacent preloading only when needed.
 */

const STORAGE_OBJECT_PUBLIC = "/storage/v1/object/public/"
const STORAGE_RENDER_PUBLIC = "/storage/v1/render/image/public/"

export function toFullResolutionMediaUrl(url: string): string {
  const raw = url.trim()
  if (!raw) return raw
  if (!raw.includes(STORAGE_RENDER_PUBLIC)) return raw
  return raw.replace(STORAGE_RENDER_PUBLIC, STORAGE_OBJECT_PUBLIC).split("?")[0]!
}
