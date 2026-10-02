import type { SupabaseClient } from "@supabase/supabase-js"

export const STORY_STORAGE_BUCKET = "stories"

const STORY_PUBLIC_MARKER = "/storage/v1/object/public/stories/"

const FOREIGN_MEDIA_COLUMNS = [
  { table: "profile_posts", column: "image_url" },
  { table: "posts", column: "image_url" },
  { table: "reels", column: "video_url" },
  { table: "reels", column: "thumbnail_url" },
  { table: "trades", column: "image_url" },
] as const

export function storyOwnedStoragePath(
  imageURL: string | null | undefined
): string | null {
  const trimmed = imageURL?.trim() ?? ""
  if (!trimmed) return null
  const idx = trimmed.indexOf(STORY_PUBLIC_MARKER)
  if (idx < 0) return null
  const raw = trimmed.slice(idx + STORY_PUBLIC_MARKER.length).split("?")[0] ?? ""
  if (!raw || raw.includes("..") || raw.startsWith("/")) return null
  try {
    const decoded = decodeURIComponent(raw)
    if (!decoded || decoded.includes("..")) return null
    return decoded
  } catch {
    return null
  }
}

export function planStoryMediaDeletion(input: {
  stories: { id: string; image_url: string | null }[]
  retainedMediaURLs: readonly string[]
}): { storyIDs: string[]; storagePaths: string[] } {
  const retained = new Set(
    input.retainedMediaURLs.map((url) => url.trim()).filter(Boolean)
  )
  const storyIDs: string[] = []
  const storagePaths = new Set<string>()

  for (const story of input.stories) {
    const id = story.id.trim()
    if (!id) continue
    storyIDs.push(id)
    const url = story.image_url?.trim() ?? ""
    if (!url || retained.has(url)) continue
    const path = storyOwnedStoragePath(url)
    if (path) storagePaths.add(path)
  }

  return { storyIDs, storagePaths: [...storagePaths] }
}

async function urlsStillReferenced(
  client: SupabaseClient,
  urls: string[],
  ignoreStoryIDs: ReadonlySet<string>
): Promise<string[]> {
  if (urls.length === 0) return []
  const retained = new Set<string>()

  const { data: stories, error: storyError } = await client
    .from("stories")
    .select("id, image_url")
    .in("image_url", urls)
  if (storyError) throw storyError
  for (const row of stories ?? []) {
    const id = String((row as { id?: string | null }).id ?? "")
    if (ignoreStoryIDs.has(id)) continue
    const url = String((row as { image_url?: string | null }).image_url ?? "").trim()
    if (url) retained.add(url)
  }

  for (const source of FOREIGN_MEDIA_COLUMNS) {
    const { data, error } = await client
      .from(source.table)
      .select(source.column)
      .in(source.column, urls)
    if (error) throw error
    for (const row of data ?? []) {
      const url = String(
        (row as Record<string, string | null | undefined>)[source.column] ?? ""
      ).trim()
      if (url) retained.add(url)
    }
  }

  return [...retained]
}

/** Deletes story-bucket objects that no remaining story, post, clip, or trade uses. */
export async function deleteUnsharedStoryStorage(
  client: SupabaseClient,
  imageURLs: readonly (string | null | undefined)[],
  options?: { ignoreStoryIDs?: readonly string[] }
): Promise<string[]> {
  const urls = [
    ...new Set(imageURLs.map((url) => url?.trim() ?? "").filter(Boolean)),
  ]
  if (urls.length === 0) return []
  const retained = await urlsStillReferenced(
    client,
    urls,
    new Set(options?.ignoreStoryIDs ?? [])
  )
  const plan = planStoryMediaDeletion({
    stories: urls.map((url, index) => ({ id: String(index), image_url: url })),
    retainedMediaURLs: retained,
  })
  if (plan.storagePaths.length === 0) return []
  const { error } = await client.storage
    .from(STORY_STORAGE_BUCKET)
    .remove(plan.storagePaths)
  if (error) throw error
  return plan.storagePaths
}
