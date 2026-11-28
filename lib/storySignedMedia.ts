import type { SupabaseClient } from "@supabase/supabase-js"
import { STORY_STORAGE_BUCKET } from "@/lib/storyMediaCleanup"
import { resolveStoryStoragePath } from "@/lib/storyStoragePath"

const DEFAULT_EXPIRES_SEC = 3600

type StoryLike = {
  storage_path?: string | null
  image_url?: string | null
}

export async function createStorySignedMediaUrl(
  client: SupabaseClient,
  story: StoryLike,
  expiresInSec = DEFAULT_EXPIRES_SEC
): Promise<string | null> {
  const path = resolveStoryStoragePath(story)
  if (!path) {
    console.info(
      `[StoryDebug] signedMedia.unresolvedPath image_url=${story.image_url ?? "nil"} storage_path=${story.storage_path ?? "nil"}`
    )
    return null
  }

  const { data, error } = await client.storage
    .from(STORY_STORAGE_BUCKET)
    .createSignedUrl(path, expiresInSec)

  if (error || !data?.signedUrl) {
    console.info(
      `[StoryDebug] signedMedia.error path=${path} message=${error?.message ?? "missing signedUrl"}`
    )
    return null
  }
  console.info(`[StoryDebug] signedMedia.ok path=${path}`)
  return data.signedUrl
}