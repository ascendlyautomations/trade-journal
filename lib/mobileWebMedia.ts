/** Widths Next.js already allows via the default imageSizes list. */
export const PHONE_WEB_THUMB_WIDTHS = [256, 384] as const

export type PhoneWebThumbWidth = (typeof PHONE_WEB_THUMB_WIDTHS)[number]

const STORAGE_OBJECT_PUBLIC = "/storage/v1/object/public/"

function canOptimizeForPhoneWeb(src: string): boolean {
  if (src.startsWith("/") && !src.startsWith("//")) return true
  try {
    const url = new URL(src)
    if (url.protocol !== "https:") return false
    if (url.hostname === "picsum.photos") return true
    return url.pathname.includes(STORAGE_OBJECT_PUBLIC)
  } catch {
    return false
  }
}

/**
 * Request a smaller rendition for a phone-web thumbnail.
 * Local public files and already-configured remote hosts go through the
 * existing Next image optimizer. Anything else keeps its original URL.
 */
export function phoneWebThumbnailSrc(
  src: string | null | undefined,
  width: PhoneWebThumbWidth
): string | null {
  const raw = src != null ? String(src).trim() : ""
  if (!raw) return null
  if (!canOptimizeForPhoneWeb(raw)) return raw
  return `/_next/image?url=${encodeURIComponent(raw)}&w=${width}&q=75`
}
