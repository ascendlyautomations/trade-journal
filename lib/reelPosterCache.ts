/** In-memory poster object URLs keyed by source video URL (session lifetime). */
const posterObjectUrlCache = new Map<string, string>()

export function getCachedReelPosterObjectUrl(
  videoUrl: string
): string | null {
  const key = videoUrl.trim()
  if (!key) return null
  return posterObjectUrlCache.get(key) ?? null
}

export function cacheReelPosterObjectUrl(
  videoUrl: string,
  objectUrl: string
): void {
  const key = videoUrl.trim()
  if (!key || !objectUrl) return
  posterObjectUrlCache.set(key, objectUrl)
}
