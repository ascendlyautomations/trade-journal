const STORY_PUBLIC_MARKER = "/storage/v1/object/public/stories/"

/** Canonical object path inside the `stories` bucket from DB fields. */
export function resolveStoryStoragePath(input: {
  storage_path?: string | null
  image_url?: string | null
}): string | null {
  const direct = input.storage_path?.trim() ?? ""
  if (direct && !direct.startsWith("http")) {
    return direct.replace(/^\/+/, "")
  }
  const image = input.image_url?.trim() ?? ""
  if (!image) return null
  if (!image.startsWith("http")) {
    return image.replace(/^\/+/, "")
  }
  const idx = image.indexOf(STORY_PUBLIC_MARKER)
  if (idx < 0) return null
  const raw = image.slice(idx + STORY_PUBLIC_MARKER.length).split("?")[0] ?? ""
  if (!raw || raw.includes("..") || raw.startsWith("/")) return null
  try {
    const decoded = decodeURIComponent(raw)
    if (!decoded || decoded.includes("..")) return null
    return decoded
  } catch {
    return null
  }
}