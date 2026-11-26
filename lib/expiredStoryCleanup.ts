import type { SupabaseClient } from "@supabase/supabase-js"
import {
  deleteExpiredStoryStoragePaths,
  storyOwnedStoragePath,
} from "@/lib/storyMediaCleanup"
import {
  storyActivityRetentionCutoffIso,
  storyPublicExpiryCutoffIso,
} from "@/lib/storyLifecycle"

const CLEANUP_BATCH = 100

export type StoryLifecyclePurgeResult = {
  expiredMediaStoryCount: number
  deletedStorageObjects: number
  purgedMetadataRows: number
}

/**
 * Stories past the 24h window: remove bucket media (DMs and cache cannot replay bytes).
 * Story rows stay for owner activity until retention purge.
 */
export async function expireStoryMedia(
  client: SupabaseClient,
  nowMs = Date.now()
): Promise<{ storyCount: number; deletedObjects: number }> {
  const publicCutoff = storyPublicExpiryCutoffIso(nowMs)
  const retentionCutoff = storyActivityRetentionCutoffIso(nowMs)

  const { data, error } = await client
    .from("stories")
    .select("id, image_url, created_at")
    .lte("created_at", publicCutoff)
    .gt("created_at", retentionCutoff)
    .limit(CLEANUP_BATCH)

  if (error) throw error

  const rows = (data ?? []) as {
    id: string
    image_url?: string | null
    created_at?: string | null
  }[]

  const paths = [
    ...new Set(
      rows
        .map((row) => storyOwnedStoragePath(row.image_url))
        .filter((path): path is string => Boolean(path))
    ),
  ]

  let deletedObjects = 0
  if (paths.length > 0) {
    deletedObjects = (await deleteExpiredStoryStoragePaths(client, paths)).length
  }

  return { storyCount: rows.length, deletedObjects }
}

/**
 * Deletes story rows once owner metadata retention has ended (engagement cascades).
 */
export async function purgeRetainedStoryMetadata(
  client: SupabaseClient,
  nowMs = Date.now()
): Promise<{ purgedRows: number }> {
  const retentionCutoff = storyActivityRetentionCutoffIso(nowMs)

  const { data, error } = await client
    .from("stories")
    .select("id")
    .lte("created_at", retentionCutoff)
    .limit(CLEANUP_BATCH)

  if (error) throw error

  const ids = (data ?? []).map((row) => String((row as { id: string }).id))
  if (ids.length === 0) {
    return { purgedRows: 0 }
  }

  const { error: deleteError } = await client.from("stories").delete().in("id", ids)
  if (deleteError) throw deleteError

  return { purgedRows: ids.length }
}

/** Cron entry: expire media, then purge metadata past retention. */
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