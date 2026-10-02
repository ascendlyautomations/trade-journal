import type { SupabaseClient } from "@supabase/supabase-js"
import { STORY_WINDOW_MS } from "@/lib/activeStories"
import { deleteUnsharedStoryStorage } from "@/lib/storyMediaCleanup"

const CLEANUP_BATCH = 100

export async function purgeExpiredStories(
  client: SupabaseClient,
  nowMs = Date.now()
): Promise<{ deletedRows: number; deletedObjects: number }> {
  const cutoff = new Date(nowMs - STORY_WINDOW_MS).toISOString()
  const { data, error } = await client
    .from("stories")
    .select("id, image_url")
    .lte("created_at", cutoff)
    .limit(CLEANUP_BATCH)

  if (error) throw error

  const expired = (data ?? []).map((row) => ({
    id: String((row as { id: string }).id),
    image_url:
      (row as { image_url?: string | null }).image_url != null
        ? String((row as { image_url?: string | null }).image_url)
        : null,
  }))
  if (expired.length === 0) {
    return { deletedRows: 0, deletedObjects: 0 }
  }

  const urls = expired
    .map((row) => row.image_url?.trim() ?? "")
    .filter(Boolean)

  let deletedObjects = 0
  if (urls.length > 0) {
    const removed = await deleteUnsharedStoryStorage(client, urls, {
      ignoreStoryIDs: expired.map((row) => row.id),
    })
    deletedObjects = removed.length
  }

  const { error: deleteError } = await client
    .from("stories")
    .delete()
    .in(
      "id",
      expired.map((row) => row.id)
    )
  if (deleteError) throw deleteError
  return { deletedRows: expired.length, deletedObjects }
}
