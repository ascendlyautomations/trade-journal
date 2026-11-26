import type { SupabaseClient } from "@supabase/supabase-js"
import {
  deleteExpiredStoryStoragePaths,
  storyOwnedStoragePath,
} from "@/lib/storyMediaCleanup"

/**
 * After a story row is removed, delete its stories-bucket object when no other
 * story row still references the same `image_url`. Ignores DM / message retention
 * so expired or deleted story media cannot be replayed from old attachments.
 */
export async function purgeStoryStorageAfterStoryRemoval(
  client: SupabaseClient,
  imageURL: string | null | undefined
): Promise<string[]> {
  const trimmed = imageURL?.trim() ?? ""
  if (!trimmed) return []

  const path = storyOwnedStoragePath(trimmed)
  if (!path) return []

  const { count, error } = await client
    .from("stories")
    .select("id", { count: "exact", head: true })
    .eq("image_url", trimmed)

  if (error) throw error
  if ((count ?? 0) > 0) return []

  return deleteExpiredStoryStoragePaths(client, [path])
}