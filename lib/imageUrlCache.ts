/** Tracks image URLs that have loaded successfully in this session (reduces flicker on remount). */

const loadedUrls = new Set<string>()

export function markImageUrlLoaded(url: string) {
  const key = url.trim()
  if (key) loadedUrls.add(key)
}

export function isImageUrlLoaded(url: string): boolean {
  return loadedUrls.has(url.trim())
}

export function clearImageUrlCache() {
  loadedUrls.clear()
}
