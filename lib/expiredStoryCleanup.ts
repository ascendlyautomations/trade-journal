import type { SupabaseClient } from "@supabase/supabase-js"

export type StoryLifecyclePurgeResult = {
  expiredMediaStoryCount: number
  deletedStorageObjects: number
  purgedMetadataRows: number
}

/**
 * Stories are retained indefinitely for the owner (archive) until explicit delete.
 * Cron remains for observability; it performs no storage or metadata deletion.
 */
export async function expireStoryMedia(
  _client: SupabaseClient,
  _nowMs = Date.now()
): Promise<{ storyCount: number; deletedObjects: number }> {
  return { storyCount: 0, deletedObjects: 0 }
}

export async function purgeRetainedStoryMetadata(
  _client: SupabaseClient,
  _nowMs = Date.now()
): Promise<{ purgedRows: number }> {
  return { purgedRows: 0 }
}

/** Cron entry: no-op after story archive rollout. */
export async function purgeExpiredStories(
  client: SupabaseClient,
  nowMs = Date.now()
): Promise<StoryLifecyclePurgeResult> {
  const media = await expireStoryMedia(client, nowMs)
  const metadata = await purgeRetainedStoryMetadata(client, nowMs)
  return {
    expiredMediaStoryCount: media.storyCount,
    deletedStorageObjects: media.deletedObjects,
    purgedMetadataRows: metadata.purgedRows,
  }
}

/** @deprecated Use {@link purgeExpiredStories}; kept for type-compat shims. */
export type LegacyPurgeResult = {
  deletedRows: number
  deletedObjects: number
}