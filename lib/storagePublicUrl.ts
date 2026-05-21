const STORAGE_PUBLIC_PREFIX = "/storage/v1/object/public"

/**
 * Resolve a Supabase storage object path (or full URL) to a public object URL.
 */
export function supabaseStoragePublicUrl(
  bucket: string,
  objectPath: string | null | undefined
): string | null {
  const raw = objectPath != null ? String(objectPath).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null

  const path = raw.replace(/^\/+/, "")
  const bucketSegment = bucket.replace(/^\/+|\/+$/g, "")
  return `${base}${STORAGE_PUBLIC_PREFIX}/${bucketSegment}/${path}`
}

/** Trade screenshot bucket (`screenshots`). */
export function tradeScreenshotPublicUrl(
  imageUrl: string | null | undefined
): string | null {
  return supabaseStoragePublicUrl("screenshots", imageUrl)
}

/** Profile wall / post images (`profile_posts`). */
export function profilePostPublicUrl(
  imageUrl: string | null | undefined
): string | null {
  return supabaseStoragePublicUrl("profile_posts", imageUrl)
}

/** Story images (`stories` bucket; callers often store full URL already). */
export function storyImagePublicUrl(
  imageUrl: string | null | undefined
): string | null {
  return supabaseStoragePublicUrl("stories", imageUrl)
}
